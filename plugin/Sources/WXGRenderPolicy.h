#ifndef WXG_RENDER_POLICY_H
#define WXG_RENDER_POLICY_H
#include <math.h>
#include <stddef.h>
static inline int WXGEffectiveFPS(int requested,int screenMaximum) {
    int maximum=screenMaximum>0?screenMaximum:60;
    if(maximum>120)maximum=120;
    if(requested<15)requested=15;
    return requested<maximum?requested:maximum;
}
// Every due scene is eligible on the same display callback. Cost changes spatial
// resolution, never inserts a cooldown or a transition/keyboard blackout.
static inline int WXGBackdropDue(double frame,double previous,double fps,int valid) {
    return !valid || frame-previous>=.93/fmax(15.,fmin(120.,fps));
}
/* FIX16: the scene read is synchronous on the main thread and shares it with
   WeChat's own scrolling, layout and animation commits. A read costing C ms
   may start again only after C/share ms of wall time, so on average no more
   than `share` of the main thread is spent reading pixels. Glass optics and
   lens motion still draw on every display callback; only background
   freshness yields when a read is expensive. A new scene (no valid sample)
   reads at once. A moved consumer whose footprint is no longer covered may
   use a relaxed share, so keyboard/transition motion refreshes sooner. */
static inline double WXGBackdropBudgetShare(double requestedPercent,int covered) {
    double share=isfinite(requestedPercent)?requestedPercent/100.:.35;
    share=fmin(.8,fmax(.2,share));
    return covered?share:fmin(.85,share+.25);
}
static inline int WXGBackdropDueWithBudget(double frame,double previous,double fps,int valid,int covered,
                                           double costMS,double requestedPercent) {
    if(!valid)return 1;
    double cadence=.93/fmax(15.,fmin(120.,fps));
    double cost=isfinite(costMS) && costMS>0?costMS/1000.:0;
    double cycle=cost/WXGBackdropBudgetShare(requestedPercent,covered);
    return frame-previous>=fmax(cadence,cycle*.93);
}
/* Exponential average of the read cost, robust to the first sample and to
   non-finite input. One slow outlier raises the next interval at once; the
   average decays over ~4 reads when the scene becomes cheap again. */
static inline double WXGBackdropCostAverage(double average,double sample) {
    if(!isfinite(sample) || sample<0)return isfinite(average) && average>0?average:0;
    if(!isfinite(average) || average<=0)return sample;
    return sample>average?average*.5+sample*.5:average*.75+sample*.25;
}
static inline double WXGBackdropInitialScale(double screenScale,double maximumFPS) {
    return fmin(fmax(1.,screenScale),maximumFPS>60?2.:1.);
}
static inline double WXGBackdropNextScale(double scale,double costMS,double fps,double screenScale,size_t captures) {
    double maximum=fmin(2.,fmax(1.,screenScale)),budget=fps>60?5.:8.;
    if(costMS>budget)return fmax(1.,scale-.25);
    if(captures>0 && captures%120==0 && costMS<budget*.35)return fmin(maximum,scale+.25);
    return fmin(maximum,fmax(1.,scale));
}
#endif
