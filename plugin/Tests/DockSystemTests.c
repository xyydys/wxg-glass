// FIX127: iOS 26's tab bar in the dock (WXGDockSystem.h): the cells that
// overlap, the lifted lens, the position spring and the hang.
#include "../Sources/WXGDockScript.h"
#include "fixtures/dock_move_ios26.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void near(double a,double b,double tolerance) {
    if(!(fabs(a-b)<=tolerance)){fprintf(stderr,"expected %.5f, got %.5f (tolerance %.5f)\n",b,a,tolerance);assert(0);}
}
int main(void) {
    // Nothing new set: the dock's own layout, bit for bit.
    const float widths[]={280,331.2f,372,398,420.5f},heights[]={54,62,68,90},gaps[]={2,4,6,14};
    for(int wi=0;wi<5;wi++)for(int hi=0;hi<4;hi++)for(int gi=0;gi<4;gi++) {
        float w=widths[wi],h=heights[hi],gap=WXGSelectionGap(gaps[gi],h);
        assert(WXGDockCellWidth(w,gap,0)==WXGSelectionWidth(w,gap));
        for(int i=-1;i<=4;i++)assert(WXGDockCellCenter(w,gap,0,i)==WXGSelectionCenter(w,gap,i));
        for(int pi=0;pi<=10;pi++)for(int ai=-2;ai<=22;ai++) {
            float press=pi/10.f,anchor=w*ai/20.f;
            WXGDockGeometry a=WXGDockLayout(w,h,gap,anchor,press,1.28f,0,1.025f,4);
            WXGDockGeometry b=WXGDockLayoutCells(w,h,gap,anchor,press,1.28f,0,1.025f,4,0,0);
            assert(!memcmp(&a,&b,sizeof a));
        }
    }
    // The system's platter: 398 x 62, the selection 4 pt inside, four cells
    // of 107.5 pt at 57.75 / 151.92 / 246.08 / 340.25 (probe 2).
    const float W=398,H=(float)WXG_DOCK26_HEIGHT,gap=(float)WXG_DOCK26_INSET,extra=(float)WXG_DOCK26_CELL_EXTRA,lift=(float)WXG_DOCK26_LIFT;
    const float growth=(float)((WXG_DOCK26_HEIGHT-2*WXG_DOCK26_INSET+WXG_DOCK26_LIFT)/WXG_DOCK26_HEIGHT);
    const float barGrowth=(float)WXG_DOCK26_BAR_GROWTH,wrap=(float)WXG_DOCK26_END_WRAP;
    near(WXGDockCellWidth(W,gap,extra),107.5,.01);
    const double centres[4]={57.75,151.92,246.08,340.25};
    for(int i=0;i<4;i++)near(WXGDockCellCenter(W,gap,extra,i),centres[i],.02);
    near(WXGDockCellPitch(W,gap,extra),94.17,.01);
    // At rest the lens is the selected cell: 107.5 x 54, 4 pt from every side
    // it touches, centred on its tab.
    for(int i=0;i<4;i++) {
        WXGDockGeometry g=WXGDockLayoutCells(W,H,gap,WXGDockCellCenter(W,gap,extra,i),0,growth,0,barGrowth,wrap,extra,lift);
        near(g.lensWidth,107.5,.01);near(g.lensHeight,54,.01);near(g.lensY,4,.01);
        near(g.lensX+g.lensWidth*.5,centres[i],.02);near(g.scale,1,1e-6);
    }
    near(WXGDockLayoutCells(W,H,gap,57.75f,0,growth,0,barGrowth,wrap,extra,lift).lensX,4,.01);
    // Lifted: 16 pt wider and taller (123.5 x 70) on the platter grown 3.55%,
    // i.e. 127.9 x 72.5 on screen; its centre from 53.6 to 344.3 in the
    // platter's own points, 48.4 to 349.5 on screen (about the middle, 199).
    WXGDockGeometry first=WXGDockLayoutCells(W,H,gap,57.75f,1,growth,0,barGrowth,wrap,extra,lift);
    WXGDockGeometry last=WXGDockLayoutCells(W,H,gap,340.25f,1,growth,0,barGrowth,wrap,extra,lift);
    near(first.lensWidth,123.5*1.0355,.05);near(first.lensHeight,70*1.0355,.05);
    near(first.lensX+first.lensWidth*.5,199+(53.6-199)*1.0355,.35);
    near(last.lensX+last.lensWidth*.5,199+(344.3-199)*1.0355,.35);
    near(first.lensY+first.lensHeight*.5,31,.01);   // still on the bar's middle
    // 4 pt above and below the bar (in the platter's points: 70 against 62).
    near((first.lensHeight-first.barHeight)*.5/first.scale,4,.01);
    // The press grows it evenly, and the width rule is the old one without 加宽.
    WXGDockGeometry half=WXGDockLayoutCells(W,H,gap,151.92f,.5f,growth,0,1,wrap,extra,lift);
    near(half.lensWidth,115.5,.01);near(half.lensHeight,62,.01);
    near(WXGDockCellLensWidth(97.5f,62,1,growth,0,0),WXGLensWidth(97.5f,62,1,growth,0),0);
    // Overlapping cells alone (no 加宽): the old "at least 1.2 cells".
    near(WXGDockLayoutCells(W,H,gap,151.92f,1,growth,0,1,wrap,extra,0).lensWidth,107.5*1.2,.02);
    // The extra is limited: a cell never wider than 1.5 quarters.
    near(WXGDockCellWidth(W,gap,500),97.5*1.5,.01);

    // The position spring: response 0.4 s, damping ratio 0.86.
    const double R=WXG_DOCK26_RESPONSE,Z=WXG_DOCK26_DAMPING;
    near(WXGDockSpringOmega(R),15.708,.001);
    double stiffness=0,friction=0;WXGDockSpringConstants(R,Z,&stiffness,&friction);
    near(stiffness,246.74,.01);near(friction,27.018,.01);   // (the system's icon spring has the same stiffness)
    near(WXGDockSpringStep(-1,R,Z),0,0);near(WXGDockSpringStep(0,R,Z),0,0);
    double peak=0,peakAt=0;
    for(int i=0;i<=2000;i++){double t=i*.001,v=WXGDockSpringStep(t,R,Z);if(v>peak){peak=v;peakAt=t;}}
    near(peak,1.005,.0015);near(peakAt,.392,.003);   // passes the tab by 0.5%
    near(WXGDockSpringStep(2,R,Z),1,1e-6);
    // The recorded moves (the app's own selection and a finger's tap) follow it.
    const struct {const double (*points)[2];int count;} moves[2]={
        {WXGDock26MoveSet,(int)(sizeof WXGDock26MoveSet/sizeof *WXGDock26MoveSet)},
        {WXGDock26MoveTap,(int)(sizeof WXGDock26MoveTap/sizeof *WXGDock26MoveTap)}};
    for(int m=0;m<2;m++) {
        double sum=0,worst=0;
        for(int i=0;i<moves[m].count;i++) {
            double e=WXGDockSpringStep(moves[m].points[i][0],R,Z)-moves[m].points[i][1];
            sum+=e*e;if(fabs(e)>worst)worst=fabs(e);
        }
        double rms=sqrt(sum/moves[m].count);
        if(!(rms<.008 && worst<.02)){fprintf(stderr,"move %d: rms %.4f worst %.4f\n",m,rms,worst);assert(0);}
    }
    // The dock's frame-by-frame spring with those constants is the same curve.
    {
        double x=0,v=0,h=1./1920,worst=0;
        for(int i=1;i<=1920;i++) {
            v+=((1-x)*stiffness-v*friction)*h;x+=v*h;
            double e=fabs(x-WXGDockSpringStep(i*h,R,Z));if(e>worst)worst=e;
        }
        assert(worst<.004);
    }
    // A scripted move: to the spring's first peak, where it stands still.
    double T=WXGDockSpringDuration(R,Z);
    near(T,.392,.003);
    near(WXGDockSpringEase(0,R,Z),0,0);near(WXGDockSpringEase(1,R,Z),1,0);near(WXGDockSpringEase(2,R,Z),1,0);
    double before=0;
    for(int i=1;i<=400;i++){double e=WXGDockSpringEase(i/400.,R,Z);assert(e>=before-1e-12 && e<=1+1e-12);before=e;}
    near(WXGDockSpringEase(.98,R,Z),1,.0005);                        // no speed left at the end
    near(WXGDockSpringEase(.25,R,Z),WXGDockSpringStep(.25*T,R,Z)/WXGDockSpringStep(T,R,Z),1e-12);
    assert(WXGDockSpringEase(.25,R,Z)>WXGScriptBezier(.25,.40,0,.30,1)+.15);   // it starts faster than the dock's bezier
    // Other settings stay finite and monotonic (no peak at or above 1).
    const double dampings[]={.5,.86,.98,1,1.2},responses[]={.2,.4,.8};
    for(int di=0;di<5;di++)for(int ri=0;ri<3;ri++) {
        double d=WXGDockSpringDuration(responses[ri],dampings[di]);
        assert(d>.05 && d<=1.2);
        double last=0;
        for(int i=1;i<=200;i++){double e=WXGDockSpringEase(i/200.,responses[ri],dampings[di]);assert(isfinite(e) && e>=last-1e-9);last=e;}
        near(last,1,0);
    }

    // The scripts. Without the spring and the hang nothing changes.
    WXGDockScript plain=WXGScriptTravel(10,100,300,94,1,0,0,2,1.4,.16,.4);
    WXGDockScript timed=WXGScriptTravelTimed(10,100,300,94,1,0,0,2,1.4,.16,.4,0);
    assert(!memcmp(&plain,&timed,sizeof plain));
    WXGDockScript untouched=plain;WXGScriptHang(&untouched,10,0);assert(!memcmp(&plain,&untouched,sizeof plain));
    near(WXGScriptMoveValue(&plain,10+plain.moveDuration*.25),100+200*WXGScriptBezier(.25,.40,0,.30,1),1e-9);
    // A glide on the spring: its own duration, the spring's curve, at rest at the end.
    WXGDockScript glide=WXGScriptGlide(5,340.25,57.75,T,0,1,0,.4);
    WXGScriptUseSpring(&glide,R,Z);
    near(glide.planEnd,5+T,1e-12);
    near(WXGScriptMoveValue(&glide,5),340.25,1e-9);near(WXGScriptMoveValue(&glide,5+T),57.75,1e-9);near(WXGScriptMoveValue(&glide,9),57.75,1e-9);
    near(WXGScriptMoveValue(&glide,5+.1),340.25+(57.75-340.25)*WXGDockSpringStep(.1,R,Z)/WXGDockSpringStep(T,R,Z),1e-9);
    double rate=1;WXGScriptMoveAt(&glide,5+T-.004,&rate);assert(fabs(rate)<12);   // pt/s: it lands softly
    for(int i=0;i<moves[1].count;i++)   // the recorded tap, within 2.5% of the way at every frame (the spring's own 2%, and the 0.5% peak the script ends on)
        near((WXGScriptMoveValue(&glide,5+moves[1].points[i][0])-340.25)/(57.75-340.25),moves[1].points[i][1],.025);
    // A travel that follows no plan takes the spring's time; one that does keeps its plan.
    WXGDockScript travel=WXGScriptTravelTimed(10,100,300,94,1,0,0,2,1.4,.16,.4,T);
    near(travel.moveDuration,T,1e-12);near(travel.planEnd,10+T,1e-12);
    WXGDockScript planned=WXGScriptTravelTimed(10,100,300,94,1,0,10.2,2,1.4,.16,.4,T);
    near(planned.moveDuration,.2,1e-12);
    WXGDockScript still=WXGScriptTravelTimed(10,100,101,94,1,0,0,2,1.4,.16,.4,T);
    near(still.moveDuration,0,0);   // already there: no move
    // The hang: a drop not before the release + 0.18 s, the lens lifted until then.
    WXGDockScript drag=WXGScriptTravelTimed(10,100,101,94,1,0,0,2,1.4,.16,.4,T);   // a drag let go on its tab: it would drop at once
    near(drag.dropStart,10,1e-12);
    WXGScriptHang(&drag,10,WXG_DOCK26_HANG);
    near(drag.dropStart,10.18,1e-12);near(drag.land,10.18+.16,1e-12);near(drag.end,drag.land+WXGScriptSettle,1e-12);
    near(WXGScriptPressValue(&drag,10.17),1,1e-9);near(WXGScriptSelectValue(&drag,10.17),0,1e-9);
    assert(WXGScriptPressValue(&drag,10.26)<.6);near(WXGScriptPressValue(&drag,drag.land),0,1e-9);near(WXGScriptSelectValue(&drag,drag.land),1,1e-9);
    assert(WXGScriptHoldsSwitch(&drag,10.3,2) && !WXGScriptHoldsSwitch(&drag,drag.land+.001,2));
    // A quick tap: released 0.08 s in, the lens goes on lifting, drops no
    // earlier than 0.26 s and no earlier than the glide's own drop.
    WXGDockScript tap=WXGScriptGlide(0,57.75,151.92,T,0,1,1,.4);
    WXGScriptUseSpring(&tap,R,Z);
    WXGScriptDrop(&tap,.08,.16);
    double own=tap.dropStart;
    WXGScriptHang(&tap,.08,WXG_DOCK26_HANG);
    near(tap.dropStart,own>.26?own:.26,1e-12);
    near(WXGScriptPressValue(&tap,tap.dropStart),.9,1e-9);
    // A drop already later than the hang is left alone.
    WXGDockScript late=tap;WXGScriptHang(&late,.08,.05);assert(!memcmp(&late,&tap,sizeof tap));
    // A glide still held (phase 1) has no drop to move.
    WXGDockScript held=WXGScriptGlide(0,57.75,151.92,T,0,1,1,.4),same=held;
    WXGScriptHang(&held,.1,.18);assert(!memcmp(&held,&same,sizeof held));
    // FIX131: the spot of light under a finger: a disc blurred by half its size, brightest in the middle, falling
    // all the way out, about half way down at the disc's edge; the bar's own veil and shadow against a button's.
    for(int k=0;k+1<WXG_DOCK_GLOW_STOPS;k++)assert(WXGDockGlowProfile(k)>WXGDockGlowProfile(k+1));
    assert(WXGDockGlowProfile(WXG_DOCK_GLOW_STOPS-1)==0.f && WXGDockGlowProfile(-3)==WXGDockGlowProfile(0) && WXGDockGlowProfile(99)==0.f);
    near(WXGDockGlowProfile(4)/WXGDockGlowProfile(0),.47,.03);
    near(WXGDockGlowProfile(0),1-exp(-2.),.002);   // the middle of a disc blurred with a Gaussian of half its radius
    assert(WXG_DOCK26_GLOW_SPOT>WXG_DOCK26_GLOW_BAR && WXG_DOCK26_BODY_VEIL<.65 && WXG_DOCK26_SHADOW<.25);
    // R8: broad iOS 26 finger glow (93 pt disc with 46.5 pt shadowRadius -> ~186 pt reach).
    near(WXGDockGlowBroadWeight(0.f),1.f,1e-6);
    near(WXGDockGlowBroadWeight(62.f),.50,.03);
    near(WXGDockGlowBroadWeight(100.f),.16,.03);
    assert(WXGDockGlowBroadWeight((float)WXG_DOCK26_GLOW_REACH)==0.f && WXGDockGlowBroadWeight(999.f)==0.f);
    for(int r=0;r<(int)WXG_DOCK26_GLOW_REACH;r+=2)assert(WXGDockGlowBroadWeight((float)r)>WXGDockGlowBroadWeight((float)(r+2)));
    puts("DockSystemTests passed");
    return 0;
}
