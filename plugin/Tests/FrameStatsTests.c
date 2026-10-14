/* FIX84: frame-rate log arithmetic (Sources/WXGFrameStats.h). */
#include "../Sources/WXGFrameStats.h"
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)
static int near(double a,double b,double eps){return fabs(a-b)<=eps;}

int main(void) {
    const double f60=1000./60,f120=1000./120;
    /* Missed refreshes: jitter is not a miss, whole refreshes are. */
    CHECK(WXGFrameMissed(f60,f60)==0,"exact frame");
    CHECK(WXGFrameMissed(f60*1.4,f60)==0,"1.4x is jitter");
    CHECK(WXGFrameMissed(f60*1.6,f60)==1,"1.6x misses one");
    CHECK(WXGFrameMissed(50,f60)==2,"50 ms at 60 Hz misses 2");
    CHECK(WXGFrameMissed(25,f120)==2,"25 ms at 120 Hz misses 2");
    CHECK(WXGFrameMissed(f60*.5,f60)==0,"a short frame misses none");
    CHECK(WXGFrameMissed(NAN,f60)==0 && WXGFrameMissed(30,0)==0 && WXGFrameMissed(-5,f60)==0 && WXGFrameMissed(INFINITY,f60)==0,"invalid input");

    /* One smooth second at 60 Hz. */
    WXGFrameStats s;WXGFrameStatsReset(&s);
    for(int i=0;i<60;i++)WXGFrameStatsAdd(&s,f60,f60);
    CHECK(s.frames==60 && s.dropped==0 && s.hitches==0 && near(s.hitchMS,0,1e-9),"smooth second");
    CHECK(near(WXGFrameStatsFPS(&s),60,1e-6),"60 fps: %f",WXGFrameStatsFPS(&s));
    CHECK(near(WXGFrameStatsPercentile(&s,.5),17,0) && near(WXGFrameStatsPercentile(&s,.99),17,0),"percentile in the 16 ms bin is 17");
    CHECK(WXGFrameStatsDropRate(&s)==0 && WXGFrameStatsHitchRatio(&s)==0,"no drops, no hitch");

    /* A 50 ms frame: 2 missed, hitch 33.3 ms. */
    WXGFrameStatsAdd(&s,50,f60);
    CHECK(s.frames==61 && s.dropped==2 && s.hitches==1 && near(s.hitchMS,50-f60,1e-9) && near(s.worstMS,50,0),"one hitch");
    CHECK(near(WXGFrameStatsDropRate(&s),2./63,1e-12),"drop rate counts the missed refreshes too");
    CHECK(near(WXGFrameStatsHitchRatio(&s),(50-f60)/((60*f60+50)/1000.),1e-9),"hitch ratio ms/s");
    CHECK(near(WXGFrameStatsPercentile(&s,1),51,0),"max percentile is the 50 ms bin's edge");

    /* 120 Hz with one 25 ms frame. */
    WXGFrameStats t;WXGFrameStatsReset(&t);
    for(int i=0;i<119;i++)WXGFrameStatsAdd(&t,f120,f120);
    WXGFrameStatsAdd(&t,25,f120);
    CHECK(t.dropped==2 && t.hitches==1,"120 Hz drop");
    CHECK(near(WXGFrameStatsFPS(&t),120000./(119*f120+25),1e-9),"120 Hz fps");
    CHECK(near(WXGFrameStatsPercentile(&t,.5),9,0) && near(WXGFrameStatsPercentile(&t,.99),9,0) && near(WXGFrameStatsPercentile(&t,.995),26,0) && near(WXGFrameStatsPercentile(&t,1),26,0),"120 Hz percentiles");

    /* Percentiles of a known spread: 90 frames of 16.7, 9 of 33.3, 1 of 120. */
    WXGFrameStats u;WXGFrameStatsReset(&u);
    for(int i=0;i<90;i++)WXGFrameStatsAdd(&u,f60,f60);
    for(int i=0;i<9;i++)WXGFrameStatsAdd(&u,2*f60,f60);
    WXGFrameStatsAdd(&u,120,f60);
    CHECK(near(WXGFrameStatsPercentile(&u,.90),17,0),"p90 %f",WXGFrameStatsPercentile(&u,.90));
    CHECK(near(WXGFrameStatsPercentile(&u,.95),34,0),"p95 %f",WXGFrameStatsPercentile(&u,.95));
    CHECK(near(WXGFrameStatsPercentile(&u,.99),34,0),"p99 %f",WXGFrameStatsPercentile(&u,.99));
    CHECK(near(WXGFrameStatsPercentile(&u,1),121,0),"p100");
    CHECK(u.dropped==9+6 && u.hitches==10,"spread drops %u hitches %u",u.dropped,u.hitches);

    /* 200 ms and more: last bin, answered with the worst. */
    WXGFrameStats v;WXGFrameStatsReset(&v);
    WXGFrameStatsAdd(&v,f60,f60);WXGFrameStatsAdd(&v,640,f60);
    CHECK(v.bins[WXG_FRAME_MS_BINS-1]==1 && near(WXGFrameStatsPercentile(&v,1),640,0),"long frame");
    CHECK(v.dropped==37,"640 ms misses 37 refreshes: %u",v.dropped);

    /* Invalid intervals are ignored. */
    unsigned before=v.frames;
    WXGFrameStatsAdd(&v,0,f60);WXGFrameStatsAdd(&v,-3,f60);WXGFrameStatsAdd(&v,NAN,f60);WXGFrameStatsAdd(&v,INFINITY,f60);WXGFrameStatsAdd(NULL,f60,f60);
    CHECK(v.frames==before,"ignored");

    /* Merging equals adding everything to one. */
    WXGFrameStats a,b,all;WXGFrameStatsReset(&a);WXGFrameStatsReset(&b);WXGFrameStatsReset(&all);
    srand(7);
    for(int i=0;i<5000;i++) {
        double e=(i&1)?f60:f120,x=e*(0.6+(rand()%1000)/250.);
        a.pluginMS+=.01;all.pluginMS+=.01;
        WXGFrameStatsAdd(i<2500?&a:&b,x,e);WXGFrameStatsAdd(&all,x,e);
    }
    WXGFrameStats m=a;WXGFrameStatsMerge(&m,&b);
    CHECK(m.frames==all.frames && m.dropped==all.dropped && m.hitches==all.hitches && near(m.totalMS,all.totalMS,1e-6) &&
          near(m.hitchMS,all.hitchMS,1e-6) && near(m.worstMS,all.worstMS,0) && near(m.pluginMS,all.pluginMS,1e-9) &&
          memcmp(m.bins,all.bins,sizeof m.bins)==0,"merge");
    CHECK(near(WXGFrameStatsPluginRatio(&all),all.pluginMS/(all.totalMS/1000.),1e-12),"plugin ratio");

    /* Expected interval: the link's own frame, else the screen's fastest. */
    CHECK(near(WXGFrameExpectedMS(f120,120),f120,0) && near(WXGFrameExpectedMS(0,120),f120,1e-12) &&
          near(WXGFrameExpectedMS(NAN,60),f60,1e-12) && near(WXGFrameExpectedMS(500,60),f60,1e-12) && near(WXGFrameExpectedMS(0,0),f60,1e-12),"expected");

    if(failures){printf("FrameStatsTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: frame-rate log (FIX84): missed refreshes vs jitter at 60/120 Hz, hitch time and ms/s, drop rate, 1 ms percentiles incl. the 200 ms+ bin, merge == single pass over 5000 frames, invalid intervals ignored.\n");
    return 0;
}
