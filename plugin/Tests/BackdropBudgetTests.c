#include "../Sources/WXGRenderPolicy.h"
#include <assert.h>
#include <stdio.h>
/* Simulate a display callback stream with a fixed synchronous read cost and
   report the share of wall time the main thread spends reading. */
static double simulate(double display,double fps,double costMS,double percent,int covered,int *reads) {
    double last=0,spent=0;int count=0,valid=0;
    for(int f=0;f<(int)display*20;f++) {
        double t=10.+f/display;
        if(WXGBackdropDueWithBudget(t,last,fps,valid,covered,costMS,percent)){last=t;valid=1;spent+=costMS/1000.;++count;}
    }
    *reads=count;return spent/20.;
}
int main(void) {
    int reads=0;
    /* Cheap reads keep the requested cadence: 60 and 120 Hz unchanged. */
    assert(simulate(60,60,2,35,1,&reads)<=.35 && reads==60*20);
    assert(simulate(120,120,1,35,1,&reads)<=.35 && reads==120*20);
    /* An expensive read (FIX14 A12 chat: 56 ms median) no longer owns the
       main thread: share stays at or under the cap (7% callback jitter allowance). */
    for(double cost=4;cost<=80;cost+=4)for(int display=60;display<=120;display+=60)for(int pct=20;pct<=80;pct+=15) {
        double share=simulate(display,display,cost,pct,1,&reads);
        double cap=pct/100.;
        /* .93 is the same jitter allowance the cadence check uses; plus the one
           immediate first read inside the 20 s window. */
        assert(share<=cap/.93+cost/1000./20.+1e-9);
        assert(reads>0);
    }
    /* Uncovered (moving) consumers get a relaxed but still bounded share. */
    double moving=simulate(60,60,17,35,0,&reads),still=simulate(60,60,17,35,1,&reads);
    assert(moving>still && moving<=.62);
    /* A new scene always reads immediately. */
    assert(WXGBackdropDueWithBudget(10,9.999,120,0,1,500,20));
    /* Non-finite input falls back to cadence only. */
    assert(WXGBackdropDueWithBudget(10+1./60,10,60,1,1,NAN,35));
    assert(WXGBackdropBudgetShare(NAN,1)==.35 && WXGBackdropBudgetShare(5,1)==.2 && WXGBackdropBudgetShare(95,1)==.8);
    /* Cost average: first sample, fast rise, slow decay, invalid samples ignored. */
    double a=WXGBackdropCostAverage(0,20);assert(a==20);
    a=WXGBackdropCostAverage(a,60);assert(a==40);
    a=WXGBackdropCostAverage(a,0);assert(a==30);
    assert(WXGBackdropCostAverage(a,NAN)==30 && WXGBackdropCostAverage(a,-1)==30);
    puts("PASS: main-thread read budget holds 20–80% caps for 4–80 ms reads at 60/120 Hz; cheap reads keep full cadence; new scenes read at once; moving consumers relaxed but bounded.");
    return 0;
}
