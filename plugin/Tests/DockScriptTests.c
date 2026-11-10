/* FIX95: the tap animation as a script for the real lens (Sources/WXGDockScript.h).
   FIX98: the colour track, the slower move, the drop's own duration, the switch
   moment and the stall-tolerant clock. FIX99: lift and colour over one share
   (0.40), a 0.16 s drop leading the arrival by 70%, the clock capped only
   around a forwarded switch. */
#include "../Sources/WXGDockScript.h"
#include <stdio.h>
static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)
static int near(double a,double b,double e){return fabs(a-b)<=e;}
// The largest jump between two samples 1/240 s apart over [a, b].
static double worstStep(const WXGDockScript *s,int track,double a,double b) {
    double worst=0,prev=0;int first=1;
    for(double t=a;t<=b;t+=1./240) {
        double v=track==0?WXGScriptPressValue(s,t):track==1?WXGScriptSelectValue(s,t):WXGScriptMoveValue(s,t);
        if(!first && fabs(v-prev)>worst)worst=fabs(v-prev);
        prev=v;first=0;
    }
    return worst;
}
int main(void) {
    /* The ease itself: ends, monotonic, the glide's shape (slow start, fast middle). */
    CHECK(near(WXGScriptBezier(0,.40,0,.30,1),0,1e-9) && near(WXGScriptBezier(1,.40,0,.30,1),1,1e-9),"bezier ends");
    double prev=-1;int mono=1;
    for(double x=0;x<=1.0001;x+=.01){double e=WXGScriptBezier(x,.40,0,.30,1);if(e<prev-1e-9)mono=0;prev=e;}
    CHECK(mono,"bezier monotonic");
    CHECK(WXGScriptBezier(.2,.40,0,.30,1)<.2 && WXGScriptBezier(.6,.40,0,.30,1)>.6,"glide: eases in, then out");
    /* Glide: FIX43 time x 1.4 for 1 tab, anchor from -> to, lifted to 0.9 and
       the colour from 1 to clear by 40% (FIX99), gradually; then held. */
    double now=10,dur=.28*(.85+.05*1)*1.4,share=.40,r;
    WXGDockScript s=WXGScriptGlide(now,100,180,dur,0,1,1,share);
    CHECK(s.phase==1 && s.index==1 && near(s.planEnd,now+dur,1e-9),"glide plan");
    CHECK(near(WXGScriptMoveAt(&s,now,&r),100,1e-6) && near(WXGScriptMoveAt(&s,now+dur,&r),180,1e-6) && near(WXGScriptMoveAt(&s,now+5,&r),180,1e-9),"glide ends");
    CHECK(near(WXGScriptPressValue(&s,now),0,1e-9) && near(WXGScriptPressValue(&s,now+dur*share),.90,1e-9) &&
          near(WXGScriptPressValue(&s,now+3),.90,1e-9),"glide press: 0 -> 0.9, held");
    CHECK(near(WXGScriptSelectValue(&s,now),1,1e-9) && near(WXGScriptSelectValue(&s,now+dur*share),0,1e-9) && near(WXGScriptSelectValue(&s,now+3),0,1e-9),
          "glide colour: 1 -> 0 by 40%%, stays clear");
    CHECK(WXGScriptSelectValue(&s,now+1./60)>.95 && WXGScriptSelectValue(&s,now+dur*share*.5)>.35 && WXGScriptSelectValue(&s,now+dur*share*.5)<.65,
          "glide colour: no jump at the touch, half way at a fifth of the move");
    CHECK(worstStep(&s,1,now,now+dur)<.065,"glide colour: at most 0.065 per 1/240 s (%.3f)",worstStep(&s,1,now,now+dur));
    double peak=0;for(double t=now;t<now+dur;t+=.004){WXGScriptMoveAt(&s,t,&r);if(r>peak)peak=r;}
    CHECK(peak>80/dur && peak<4*80/dur,"glide speed peaks between mean and 4x mean (%.0f pt/s)",peak);
    /* A held press already deeper than the lift stays there; a touch during a
       landing starts from the colour it had. */
    WXGDockScript deep=WXGScriptGlide(now,0,80,.25,.97,.4,1,share);
    CHECK(near(WXGScriptPressValue(&deep,now+.2),.97,1e-9) && near(WXGScriptSelectValue(&deep,now),.4,1e-9),"deep press kept, colour from where it was");
    /* Drop (0.16 s): released early (0.1 s in): starts 70% of it before the
       lens arrives, down 30% of it after; the press keeps lifting until then. */
    double drop=.16;
    WXGDockScript a=s;double rel=now+.10;
    WXGScriptDrop(&a,rel,drop);
    CHECK(a.phase==2 && near(a.dropStart,s.planEnd-.7*drop,1e-9) && near(a.land,a.dropStart+drop,1e-9) && near(a.end,a.land+.05,1e-9),
          "early release: the drop around the arrival (start %.3f, land %.3f)",a.dropStart-now,a.land-now);
    CHECK(near(WXGScriptPressValue(&a,rel),WXGScriptPressValue(&s,rel),1e-12) && near(WXGScriptPressValue(&a,a.dropStart),.90,1e-9) &&
          near(WXGScriptPressValue(&a,a.land),0,1e-9) && near(WXGScriptPressValue(&a,a.end+1),0,1e-9),"drop press: the glide's until the drop, then down");
    CHECK(near(WXGScriptSelectValue(&a,a.dropStart),0,1e-9) && near(WXGScriptSelectValue(&a,a.land),1,1e-9) && near(WXGScriptSelectValue(&a,a.end+1),1,1e-9),
          "drop colour: back to the pill over the drop");
    double mid=WXGScriptSelectValue(&a,a.dropStart+drop*.5);
    CHECK(mid>.35 && mid<.65,"drop colour: half way half way through (%.2f)",mid);
    CHECK(worstStep(&a,0,now,a.end+.1)<.065 && worstStep(&a,1,now,a.end+.1)<.065,"no jumps through the whole tap (press %.3f, colour %.3f)",
          worstStep(&a,0,now,a.end+.1),worstStep(&a,1,now,a.end+.1));
    CHECK(near(WXGScriptMoveAt(&a,s.planEnd,&r),180,1e-6),"the glide keeps going to the tab");
    double total=a.land-now;
    CHECK(total>.36 && total<.44,"a 1-tab tap is down in about 0.4 s (%.3f s; FIX97 0.26, FIX98 0.53)",total);
    CHECK(a.land-s.planEnd<.06,"down within 0.06 s of arriving (%.3f)",a.land-s.planEnd);
    CHECK(a.dropStart-(now+dur*share)<.12,"clear for under 0.12 s before the colour comes back (%.3f)",a.dropStart-(now+dur*share));
    double pv=2;int down=1;
    for(double t=a.dropStart;t<=a.end;t+=.002){double v=WXGScriptPressValue(&a,t);if(v<-1e-9 || v>1+1e-9 || v>pv+1e-9)down=0;pv=v;}
    CHECK(down,"drop press within 0..1 and only falling once it drops");
    double sv=-1;int up=1;
    for(double t=a.dropStart;t<=a.end;t+=.002){double v=WXGScriptSelectValue(&a,t);if(v<sv-1e-9)up=0;sv=v;}
    CHECK(up,"drop colour only rising");
    /* Released late (after the move): the drop from the release, 0.16 s. */
    WXGDockScript b=s;double late=now+.6;WXGScriptDrop(&b,late,drop);
    CHECK(near(b.dropStart,late,1e-9) && near(b.land,late+drop,1e-9),"late release: the drop from now");
    WXGDockScript c=s;WXGScriptDrop(&c,now+.6,.05);
    CHECK(near(c.land-(now+.6),.10,1e-9),"a very short drop: still at least 0.1 s");
    /* Travel (a drag released on another tab): 0.27 s x (0.85 + 0.05 x tabs) x scale. */
    WXGDockScript t=WXGScriptTravel(now,100,180,80,1,0,0,1,1.4,drop,share);
    CHECK(near(t.moveDuration,.27*.90*1.4,1e-9) && near(t.planEnd,now+t.moveDuration,1e-9),"travel: 1 tab x 1.4");
    CHECK(near(t.dropStart,now+t.moveDuration-.7*drop,1e-9) && near(t.land,t.dropStart+drop,1e-9) && near(t.end,t.land+.05,1e-9),"travel: the drop around the arrival");
    CHECK(near(WXGScriptPressValue(&t,now),1,1e-9) && near(WXGScriptPressValue(&t,t.land),0,1e-9) && near(WXGScriptSelectValue(&t,now),0,1e-9) &&
          near(WXGScriptSelectValue(&t,t.land),1,1e-9),"travel: from the drag's press and colour, down and coloured at the landing");
    CHECK(worstStep(&t,0,now,t.end)<.065 && worstStep(&t,1,now,t.end)<.065,"travel: no jumps (press %.3f, colour %.3f)",worstStep(&t,0,now,t.end),worstStep(&t,1,now,t.end));
    WXGDockScript plan=WXGScriptTravel(now,100,180,80,.9,0,now+.05,1,1.4,drop,share);
    CHECK(near(plan.moveDuration,.12,1e-9),"a glide's plan, at least 0.12 s");
    WXGDockScript still=WXGScriptTravel(now,100,101,80,.95,.05,0,1,1.4,drop,share);
    CHECK(still.moveDuration==0 && near(WXGScriptMoveAt(&still,now,&r),101,1e-9) && near(still.dropStart,now,1e-9) && near(still.land,now+drop,1e-9),"no move: drop only");
    CHECK(near(WXGScriptPressValue(&still,still.land),0,1e-9) && near(WXGScriptSelectValue(&still,now),.05,1e-9) && near(WXGScriptSelectValue(&still,still.land),1,1e-9),
          "no move: down, the colour back over the drop");
    WXGDockScript lift=WXGScriptTravel(now,0,240,80,.3,.8,0,3,1,drop,share);
    CHECK(near(WXGScriptPressValue(&lift,now+lift.moveDuration*share),.90,1e-9) && WXGScriptSelectValue(&lift,lift.dropStart)<.1 &&
          lift.dropStart>=now+lift.moveDuration*share+.02-1e-9,"a long travel lifts and (nearly) clears first (%.3f)",WXGScriptSelectValue(&lift,lift.dropStart));
    /* The switch moment. */
    CHECK(WXGScriptHoldsSwitch(&s,now+.05,0) && WXGScriptHoldsSwitch(&s,now+.05,1) && WXGScriptHoldsSwitch(&s,now+.05,2),"finger on a glide: always held");
    CHECK(!WXGScriptHoldsSwitch(&a,rel,0),"moment 0: at the release");
    CHECK(WXGScriptHoldsSwitch(&a,now+dur*.79,1) && !WXGScriptHoldsSwitch(&a,now+dur*.81,1),"moment 1: until 80%% of the move");
    CHECK(WXGScriptHoldsSwitch(&a,a.land-.01,2) && !WXGScriptHoldsSwitch(&a,a.land+.001,2),"moment 2: until down (FIX95)");
    CHECK(!WXGScriptHoldsSwitch(&still,now,1),"moment 1, nothing to move: at once");
    WXGDockScript none={0};
    CHECK(!WXGScriptHoldsSwitch(&none,now,2),"no script: never");
    /* The clock: real time, a stall counts one capped step. */
    double clock=100;
    clock=WXGScriptClockStep(clock,0,1./120,WXGScriptClockCap);
    CHECK(near(clock,100+1./120,1e-12),"clock: a frame");
    clock=WXGScriptClockStep(clock,1./120,1./120+.18,WXGScriptClockCap);
    CHECK(near(clock,100+1./120+1./24,1e-12),"clock: a 0.18 s stall advances 1/24 s");
    CHECK(near(WXGScriptClockStep(clock,5,4,WXGScriptClockCap),clock,0),"clock: never backwards");
    CHECK(near(WXGScriptClockStep(0,0,1./30,WXGScriptClockCap),1./30,1e-12),"clock: a 30 fps frame is not cut");
    /* FIX99: only around a forwarded switch; slow frames elsewhere on real time;
       never more than 0.5 s behind. */
    {double c2=0,l2=0;for(int i=1;i<=40;i++){double rr=i*.06;c2=WXGScriptClockAdvance(c2,l2,rr,0);l2=rr;}
     CHECK(near(c2,2.4,1e-9),"clock: 40 frames of 60 ms (a busy cold start) on real time (%.3f)",c2);}
    CHECK(near(WXGScriptClockAdvance(5,5,5.18,5.0),5+1./60,1e-12),"clock: the stall after a forwarded switch counts one 60 Hz frame");
    CHECK(near(WXGScriptClockAdvance(5,5.2,5.28,5.0),5+1./30,1e-12),"clock: a busy frame after it at most 1/30 s (FIX100)");
    CHECK(near(WXGScriptClockAdvance(5,5.2,5.225,5.0),5.025,1e-12),"clock: a 40 fps frame after it is not cut");
    CHECK(near(WXGScriptClockAdvance(5,5,5.18,3.0),5.18,1e-12),"clock: a stall long after one is not");
    CHECK(near(WXGScriptClockAdvance(5,5,7,5.0),6.5,1e-12),"clock: at most 0.5 s behind");
    CHECK(near(WXGScriptClockAdvance(5,6,5.5,5.0),5,0),"clock: never backwards (advance)");
    /* A tap frame by frame (120 Hz) with WeChat switching at the moment
       chosen (1: 80% of the move) and stalling the main thread 0.18 s: on the
       capped clock the lens pauses, then goes on with no jump; on real time
       (FIX95..97 used CACurrentMediaTime) it would jump. */
    for(int capped=1;capped>=0;capped--) {
        double real=0,clock=0,last=0,px=-1,pp=-1,ps=-1,jx=0,jp=0,js=0;int switched=0,frames=0;
        WXGDockScript k=WXGScriptGlide(0,100,180,dur,0,1,1,share);double switchAt=0;
        while(real<1.2) {
            double next=real+1./120;
            if(!switched && k.phase==2 && !WXGScriptHoldsSwitch(&k,clock,1)){switched=1;switchAt=real;next=real+.18;}   // the switch, then the stall
            clock=capped?WXGScriptClockAdvance(clock,last,next,switchAt):next;last=real=next;
            if(k.phase==1 && clock>=.10)WXGScriptDrop(&k,clock,drop);
            double x=WXGScriptMoveValue(&k,clock),pr=WXGScriptPressValue(&k,clock),se=WXGScriptSelectValue(&k,clock);
            if(px>=0){if(fabs(x-px)>jx)jx=fabs(x-px);if(fabs(pr-pp)>jp)jp=fabs(pr-pp);if(fabs(se-ps)>js)js=fabs(se-ps);}
            px=x;pp=pr;ps=se;++frames;
        }
        if(capped) {
            CHECK(switched,"the switch fires");
            CHECK(jx<5 && jp<.25 && js<.25,"capped clock through a 0.18 s stall: largest frame step x %.2f pt, press %.3f, colour %.3f",jx,jp,js);
            CHECK(near(px,180,1e-6) && near(pp,0,1e-9) && near(ps,1,1e-9),"and it still ends on the tab, down, coloured");
        }else {CHECK(jx>10 || jp>.3 || js>.3,"(real time would jump)");printf("  (on real time the 0.18 s stall jumps x %.1f pt, press %.2f, colour %.2f in one frame)\n",jx,jp,js);}
    }
    /* FIX100: WeChat switching at the touch (as its own tab bar does): the
       stall comes before the lens has moved; then three busy frames; the lens
       moves at most one 60 Hz frame across the stall and 1/30 s per busy frame
       (no jump), lags at most 0.5 s, and still lands. */
    {
        double real=0,clock=0,last=0,pp=0,switchAt=.005,worstStall=0,worstBusy=0,lag=0;int busy=0;
        WXGDockScript k=WXGScriptGlide(0,100,180,dur,0,1,1,share);
        while(real<1.6) {
            double next=real+1./60;int stall=0,slow=0;
            if(real<switchAt && next>=switchAt){next=switchAt+.20;stall=1;}            // the switch (0.2 s)
            else if(real>switchAt && busy<3){next=real+.09;++busy;slow=1;}           // WeChat's layout after it
            double before=clock;
            clock=WXGScriptClockAdvance(clock,last,next,switchAt);last=real=next;
            if(stall && clock-before>worstStall)worstStall=clock-before;
            if(slow && clock-before>worstBusy)worstBusy=clock-before;
            if(real-clock>lag)lag=real-clock;
            if(k.phase==1 && clock>=.10)WXGScriptDrop(&k,clock,drop);
            pp=WXGScriptPressValue(&k,clock);
        }
        CHECK(worstStall<=1./60+1e-9 && worstBusy<=1./30+1e-9 && lag<=.5+1e-9,"switch at the touch: the stall %.4f s, a busy frame %.4f s, lag %.3f s",worstStall,worstBusy,lag);
        CHECK(near(WXGScriptMoveValue(&k,clock),180,1e-6) && near(pp,0,1e-9) && near(WXGScriptSelectValue(&k,clock),1,1e-9),"switch at the touch: still lands, down, coloured");
    }
    /* FIX100: shifted by a stall, the script is the same curve later. */
    {
        WXGDockScript a2=WXGScriptGlide(now,100,180,dur,0,1,1,share);WXGScriptDrop(&a2,now+.1,drop);
        WXGDockScript b2=a2;WXGScriptShift(&b2,.7);
        int same=1;
        for(double x=now-.2;x<now+1;x+=.01)
            if(!near(WXGScriptMoveValue(&a2,x),WXGScriptMoveValue(&b2,x+.7),1e-9) || !near(WXGScriptPressValue(&a2,x),WXGScriptPressValue(&b2,x+.7),1e-9) ||
               !near(WXGScriptSelectValue(&a2,x),WXGScriptSelectValue(&b2,x+.7),1e-9))same=0;
        CHECK(same && near(b2.land,a2.land+.7,1e-9) && near(b2.end,a2.end+.7,1e-9),"shift: the same curve 0.7 s later");
        WXGDockScript n2={0};WXGScriptShift(&n2,1);
        CHECK(n2.moveStart==0 && n2.land==0,"shift: nothing to shift");
    }
    /* FIX101: the calm wait: three frames on time in a row, a late one starts
       again, 0.6 s at most. */
    {
        int calm=0;
        CHECK(WXGScriptCalmWait(&calm,0,1./60,0),"calm: the first look, no interval yet");
        CHECK(WXGScriptCalmWait(&calm,.017,1./60,.02) && WXGScriptCalmWait(&calm,.016,1./60,.04),"calm: two on time, still waiting");
        CHECK(WXGScriptCalmWait(&calm,.15,1./60,.19) && calm==0,"calm: a slow one starts the count again");
        WXGScriptCalmWait(&calm,.017,1./60,.21);WXGScriptCalmWait(&calm,.017,1./60,.23);
        CHECK(!WXGScriptCalmWait(&calm,.016,1./60,.25),"calm: three on time: go");
        int c2=0;
        CHECK(WXGScriptCalmWait(&c2,.7,1./60,.71),"calm: past 0.6 s, not straight after a long frame");
        CHECK(!WXGScriptCalmWait(&c2,.017,1./60,.73),"calm: past 0.6 s, one on time is enough");
        int c4=0;
        CHECK(!WXGScriptCalmWait(&c4,.3,1./60,1.21),"calm: 1.2 s at most");
        int c3=0;WXGScriptCalmWait(&c3,.0085,1./120,.01);WXGScriptCalmWait(&c3,.02,1./120,.03);
        CHECK(c3==2,"calm: at 120 Hz a 20 ms frame still counts (22 ms floor)");
    }
    /* FIX102: time scaling about a pivot keeps the curve; the catch-up after a
       pause shortens what is left by 60% of the pause, at most a quarter. */
    {
        WXGDockScript a3=WXGScriptGlide(now,100,180,dur,0,1,1,share);WXGScriptDrop(&a3,now+.1,drop);
        WXGDockScript b3=a3;double pivot=now+.15,f=.8;WXGScriptScaleTime(&b3,pivot,f);
        int same=1;
        for(double x=pivot;x<a3.end+.1;x+=.005){double y=pivot+(x-pivot)*f;
            if(!near(WXGScriptMoveValue(&a3,x),WXGScriptMoveValue(&b3,y),1e-7) || !near(WXGScriptPressValue(&a3,x),WXGScriptPressValue(&b3,y),1e-7) ||
               !near(WXGScriptSelectValue(&a3,x),WXGScriptSelectValue(&b3,y),1e-7))same=0;}
        CHECK(same && near(b3.end-pivot,(a3.end-pivot)*f,1e-9),"scale: the same curve, 0.8 x as long from the pivot");
        WXGDockScript c3=a3;double before=c3.end-pivot,k=WXGScriptCatchUp(&c3,pivot,.1);
        CHECK(near(c3.end-pivot,before-.06,1e-9) && k<1,"catch-up: 0.1 s pause, 0.06 s shorter (%.3f)",k);
        WXGDockScript d3=a3;WXGScriptCatchUp(&d3,pivot,2);
        CHECK(near(d3.end-pivot,before*.75,1e-9),"catch-up: at most a quarter");
        WXGDockScript e3=a3;CHECK(WXGScriptCatchUp(&e3,pivot,.005)==1,"catch-up: nothing for a tiny pause");
        CHECK(near(WXGScriptMoveValue(&c3,pivot),WXGScriptMoveValue(&a3,pivot),1e-9),"catch-up: no jump at the pivot");
    }
    /* Everything finite. */
    int finite=1;
    for(double x=now-1;x<now+2;x+=.003){double rr=0,v=WXGScriptMoveAt(&t,x,&rr);if(!isfinite(v) || !isfinite(rr))finite=0;v=WXGScriptPressAt(&t,x,&rr);if(!isfinite(v) || !isfinite(rr))finite=0;
        v=WXGScriptSelectValue(&a,x);if(!isfinite(v) || v<-1e-9 || v>1+1e-9)finite=0;}
    CHECK(finite,"finite values and rates, colour within 0..1");
    /* FIX131: on the system's spring the lift and the drop follow iOS 26's own curves (nine recorded taps): the
       lift half way after 0.07 s and at 90 % after 0.155 s of its 0.245 s, the drop half down after 0.06 s and
       90 % down after 0.15 s of its 0.23 s; without the spring the script is as it was, bit for bit. */
    {
        double move=WXGDockSpringDuration(.40,.86),share=WXG_SCRIPT26_LIFT_TIME/move;
        WXGDockScript plain=WXGScriptGlide(10,60,154,move,0,1,1,share),sys=plain,off=plain;
        WXGScriptUseSpring(&sys,.40,.86);WXGScriptUseSpring(&off,0,.86);
        int same=1;
        for(double t=10;t<=10.6;t+=1./240)if(WXGScriptPressValue(&plain,t)!=WXGScriptPressValue(&off,t))same=0;
        CHECK(same,"no spring: the script's own lift");
        CHECK(near(WXGScriptPressValue(&sys,10+.068)/.9,.50,.03) && near(WXGScriptPressValue(&sys,10+.155)/.9,.90,.03) && near(WXGScriptPressValue(&sys,10+.245),.9,1e-9),
              "the system's lift: half at 0.07 s, 90%% at 0.155 s (%.3f %.3f)",WXGScriptPressValue(&sys,10+.068)/.9,WXGScriptPressValue(&sys,10+.155)/.9);
        CHECK(WXGScriptPressValue(&sys,10+.03)>WXGScriptPressValue(&plain,10+.03)+.05,"quick at once (%.3f against %.3f)",WXGScriptPressValue(&sys,10+.03),WXGScriptPressValue(&plain,10+.03));
        CHECK(worstStep(&sys,0,10,10.7)<.06,"no jump in the lift (%.3f)",worstStep(&sys,0,10,10.7));
        WXGDockScript a=sys,b=plain;
        WXGScriptDrop(&a,10.09,WXG_SCRIPT26_DROP_TIME);WXGScriptDrop(&b,10.09,WXG_SCRIPT26_DROP_TIME);
        double start=a.dropStart,top=WXGScriptPressValue(&a,start);
        CHECK(near(a.land-a.dropStart,WXG_SCRIPT26_DROP_TIME,1e-9) && top>.85,"the drop's span (%.3f from %.3f)",a.land-a.dropStart,top);
        CHECK(near(WXGScriptPressValue(&a,start+.062)/top,.50,.03) && near(WXGScriptPressValue(&a,start+.150)/top,.10,.03) && WXGScriptPressValue(&a,a.land)==0,
              "the system's drop: half after 0.06 s, 10%% left after 0.15 s (%.3f %.3f)",WXGScriptPressValue(&a,start+.062)/top,WXGScriptPressValue(&a,start+.150)/top);
        CHECK(WXGScriptPressValue(&a,start+.03)<WXGScriptPressValue(&b,start+.03)-.05,"down quicker at once than the in-out drop");
        CHECK(worstStep(&a,0,10,10.9)<.06,"no jump in the drop (%.3f)",worstStep(&a,0,10,10.9));
    }
    if(failures){printf("DockScriptTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: tap animation script (FIX95/98/99): glide (FIX43 timing x scale, lift and colour over 40%%), 0.16 s drop leading the arrival (down 0.05 s after), travel, no jumps, switch moments 0/1/2, clock capped only around a forwarded switch (max 0.5 s behind), finite rates.\n");
    return 0;
}
