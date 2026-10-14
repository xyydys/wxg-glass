#include "../Sources/WXGMotionPrediction.h"
#include <assert.h>
#include <stdio.h>
/* UIKit-like push: ease-out cubic over 0.35 s from x0 to x1 (model = x1). */
static double push(double t,double x0,double x1) {
    double u=t<0?0:t>.35?1:t/.35; return x0+(x1-x0)*(1-pow(1-u,3));
}
int main(void) {
    double worstRaw=0,worstPred=0,sumRaw=0,sumPred=0;int n=0;
    for(int hz=60;hz<=120;hz+=60)for(double lead=.016;lead<=.050;lead+=.008) {
        WXGMotionTrack k={0};
        for(int f=0;f<(int)(.5*hz);f++) {
            double t=f/(double)hz,p=push(t,414,0);
            WXGMotionSample s={p,0,0,0,t};
            if(k.count) {
                double dx,dy;WXGMotionPredict(WXGMotionBase(k,t),s,lead,0,0,160,&dx,&dy);
                double truth=push(t+lead,414,0),raw=fabs(p-truth),pred=fabs(p+dx-truth);
                /* never past the end state, never away from it */
                assert(p+dx>=-1e-9 && dx<=1e-9 && dy==0);
                if(t>2./hz && t<.35){sumRaw+=raw;sumPred+=pred;++n;if(raw>worstRaw)worstRaw=raw;if(pred>worstPred)worstPred=pred;}
            }
            k=WXGMotionRecord(k,s);
        }
    }
    printf("push 414pt/0.35s ease-out, lead 16-48 ms, 60/120 Hz: mean error %.1f -> %.1f pt, worst %.1f -> %.1f pt\n",
           sumRaw/n,sumPred/n,worstRaw,worstPred);
    assert(sumPred<sumRaw*.45 && worstPred<worstRaw*.6);
    /* Model-driven scroll at constant 1800 pt/s: exact for the model lead. */
    WXGMotionTrack k={0};
    for(int f=0;f<30;f++) {
        double t=f/60.,y=-1800*t;WXGMotionSample s={0,y,0,y,t};
        if(k.count){double dx,dy;WXGMotionPredict(WXGMotionBase(k,t),s,.04,1/60.,0,160,&dx,&dy);assert(fabs(dy+30)<1e-6 && dx==0);}
        k=WXGMotionRecord(k,s);
    }
    /* Model lead never exceeds one observed step (teleport is repeated at most once). */
    {WXGMotionSample a={0,0,0,0,0},b={0,500,0,500,1/60.};double dx,dy;
     WXGMotionPredict(a,b,.05,.05,0,1000,&dx,&dy);assert(dy<=500+1e-9 && dy>0);}
    /* Animation start: model jumped to the end, presentation barely moved. */
    {WXGMotionSample a={0,0,0,0,0},b={-3,0,-138,0,1/60.};double dx,dy;
     WXGMotionPredict(a,b,.04,.016,0,160,&dx,&dy);assert(dx<0 && dx>=-135-1e-9);}
    /* At rest, after completion, or with no time base: nothing. */
    {WXGMotionSample a={5,5,5,5,0},b={5,5,5,5,1/60.};double dx,dy;assert(!WXGMotionPredict(a,b,.04,.016,0,160,&dx,&dy));}
    {WXGMotionSample a={10,0,0,0,0},b={0,0,0,0,1/60.};double dx,dy;assert(!WXGMotionPredict(a,b,.04,.016,0,160,&dx,&dy));}
    {WXGMotionSample a={0,0,0,0,0},b={9,0,99,0,0};double dx,dy;assert(!WXGMotionPredict(a,b,.04,.016,0,160,&dx,&dy));}
    /* Interactive (finger-driven, paused animation): only the model lead. */
    {WXGMotionSample a={100,0,300,0,0},b={110,0,300,0,.01};double dx,dy;
     WXGMotionPredict(a,b,.05,.008,1,160,&dx,&dy);assert(fabs(dx-8)<1e-9);}
    /* Moving away from the end state (spring overshoot) is not extrapolated. */
    {WXGMotionSample a={0,0,10,0,0},b={-2,0,10,0,.01};double dx,dy;assert(!WXGMotionPredict(a,b,.04,.016,0,160,&dx,&dy));}
    /* Same-frame re-evaluation keeps the previous base. */
    WXGMotionTrack q={0};WXGMotionSample s0={0,0,0,0,0},s1={10,0,10,0,.016},s2={10.1,0,10.1,0,.017};
    q=WXGMotionRecord(q,s0);q=WXGMotionRecord(q,s1);
    assert(WXGMotionBase(q,.017).t==0);
    q=WXGMotionRecord(q,s2);assert(q.previous.t==0 && q.last.t==.017);
    puts("PASS: display-time prediction cuts push lag error about 4x without passing the end state; exact for steady scroll; teleports, rest, completion, interactive and overshoot bounded.");
    return 0;
}
