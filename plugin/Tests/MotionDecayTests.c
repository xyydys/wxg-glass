#include "../Sources/WXGMotionPrediction.h"
#include <assert.h>
#include <stdio.h>
/* Normalised progress curves u(t/T) in [0,1]. */
static double easeOut(double x){return 1-pow(1-x,3);}
static double easeInOut(double x){return x<.5?4*x*x*x:1-pow(-2*x+2,3)/2;}
static double spring(double x){double w=11.;return 1-(1+w*x)*exp(-w*x);}           /* critically damped */
typedef double (*Curve)(double);
typedef struct {double mean,worst,tailAhead,tailBehind;int pastEnd;} Score;
static Score run(Curve c,double T,double dist,int hz,double lead,int three) {
    Score s={0};int n=0,tn=0;WXGMotionTrack k={0};
    for(int f=0;f<(int)((T+.1)*hz);f++) {
        double t=f/(double)hz,x=t/T,p=dist*c(x>1?1:x),truthX=(t+lead)/T,truth=dist*c(truthX>1?1:truthX);
        WXGMotionSample sm={p,0,dist,0,t};
        if(k.count) {
            double dx=0,dy=0;
            if(three)WXGMotionPredict2(WXGMotionOlder(k,t),WXGMotionBase(k,t),sm,lead,0,0,400,&dx,&dy);
            else WXGMotionPredict(WXGMotionBase(k,t),sm,lead,0,0,400,&dx,&dy);
            double e=(p+dx)-truth;
            if(p+dx>dist+1e-9)s.pastEnd=1;
            if(t>2./hz && t<T){s.mean+=fabs(e);if(fabs(e)>s.worst)s.worst=fabs(e);++n;}
            if(t>.6*T && t<T){if(e>0)s.tailAhead+=e;else s.tailBehind-=e;++tn;}
        }
        k=WXGMotionRecord(k,sm);
    }
    s.mean/=n;s.tailAhead/=tn;s.tailBehind/=tn;return s;
}
int main(void) {
    const char *names[]={"ease-out","ease-in-out","spring"};Curve curves[]={easeOut,easeInOut,spring};
    double totalLinear=0,totalDecay=0,tailLinear=0,tailDecay=0;
    for(int c=0;c<3;c++) {
        Score L={0},D={0};int runs=0;
        for(int hz=60;hz<=120;hz+=60)for(double lead=.016;lead<=.0481;lead+=.008)for(double T=.25;T<=.5001;T+=.125) {
            Score a=run(curves[c],T,414,hz,lead,0),b=run(curves[c],T,414,hz,lead,1);
            assert(!a.pastEnd && !b.pastEnd);
            L.mean+=a.mean;L.tailAhead+=a.tailAhead;if(a.worst>L.worst)L.worst=a.worst;
            D.mean+=b.mean;D.tailAhead+=b.tailAhead;if(b.worst>D.worst)D.worst=b.worst;
            /* Never worse than the FIX17 linear model, on average or worst case. */
            assert(b.mean<=a.mean*1.05+.05 && b.worst<=a.worst+1e-6);
            ++runs;
        }
        printf("%-12s linear: mean %5.2f worst %6.2f tail-ahead %5.2f | 3-sample: mean %5.2f worst %6.2f tail-ahead %5.2f pt\n",
               names[c],L.mean/runs,L.worst,L.tailAhead/runs,D.mean/runs,D.worst,D.tailAhead/runs);
        totalLinear+=L.mean/runs;totalDecay+=D.mean/runs;tailLinear+=L.tailAhead/runs;tailDecay+=D.tailAhead/runs;
    }
    assert(totalDecay<totalLinear*.75);
    assert(tailDecay<tailLinear*.5);
    /* Exponential scroll deceleration (model-driven): exact up to sampling. */
    WXGMotionTrack k={0};double worst=0;
    for(int f=0;f<60;f++) {
        double t=f/60.,y=-2000/4.*(1-exp(-4*t));WXGMotionSample s={0,y,0,y,t};
        if(k.count>2) {
            double dx,dy,lead=1/60.;WXGMotionPredict2(WXGMotionOlder(k,t),WXGMotionBase(k,t),s,.04,lead,0,160,&dx,&dy);
            double truth=-2000/4.*(1-exp(-4*(t+lead)));if(fabs(y+dy-truth)>worst)worst=fabs(y+dy-truth);
        }
        k=WXGMotionRecord(k,s);
    }
    printf("scroll deceleration 2000 pt/s, k=4/s: worst model-lead error %.3f pt\n",worst);
    assert(worst<.05);
    puts("PASS: decay-aware prediction lowers transition error and removes most early arrival in decelerating tails; never past the end state; exact for exponential scroll deceleration.");
    return 0;
}
