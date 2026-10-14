#ifndef WXG_FRAME_STATS_H
#define WXG_FRAME_STATS_H
#include <math.h>
#include <string.h>
/* FIX84: the frame-rate log (WXGPerfMonitor.m), pure C.
   One display callback on the main thread is one frame the app could show.
   Its interval against the expected one (the display's current frame
   duration, 16.7 ms at 60 Hz, 8.3 ms at 120 Hz) gives:
   - missed (dropped) frames: the interval rounded to whole refreshes, minus
     one (1.4 x expected is jitter, 1.6 x is one refresh missed);
   - hitch time: for a frame that missed a refresh, how much longer than
     expected it took (Apple's hitch time; per second of time it is the
     hitch ratio, ms/s);
   - a 1 ms histogram of intervals (0..199 ms, the last bin 200 ms and more)
     for percentiles. */
#define WXG_FRAME_MS_BINS 201
typedef struct {
    unsigned frames,dropped,hitches;          // hitches: frames that missed at least one refresh
    double totalMS,hitchMS,worstMS,pluginMS;  // pluginMS: the plugin's main-thread time meanwhile
    unsigned bins[WXG_FRAME_MS_BINS];
} WXGFrameStats;

static inline void WXGFrameStatsReset(WXGFrameStats *s) {if(s)memset(s,0,sizeof *s);}
static inline unsigned WXGFrameMissed(double intervalMS,double expectedMS) {
    if(!(expectedMS>0.) || !(intervalMS>0.) || !isfinite(intervalMS) || !isfinite(expectedMS))return 0;
    double n=floor(intervalMS/expectedMS+.5)-1.;
    return n>0.?(n>1e6?1000000u:(unsigned)n):0u;
}
static inline void WXGFrameStatsAdd(WXGFrameStats *s,double intervalMS,double expectedMS) {
    if(!s || !(intervalMS>0.) || !isfinite(intervalMS))return;
    unsigned missed=WXGFrameMissed(intervalMS,expectedMS);
    s->frames++;s->dropped+=missed;s->totalMS+=intervalMS;
    if(missed){s->hitches++;s->hitchMS+=intervalMS-expectedMS;}
    if(intervalMS>s->worstMS)s->worstMS=intervalMS;
    int bin=intervalMS>=(double)(WXG_FRAME_MS_BINS-1)?WXG_FRAME_MS_BINS-1:(int)intervalMS;
    s->bins[bin]++;
}
static inline void WXGFrameStatsMerge(WXGFrameStats *into,const WXGFrameStats *from) {
    if(!into || !from)return;
    into->frames+=from->frames;into->dropped+=from->dropped;into->hitches+=from->hitches;
    into->totalMS+=from->totalMS;into->hitchMS+=from->hitchMS;into->pluginMS+=from->pluginMS;
    if(from->worstMS>into->worstMS)into->worstMS=from->worstMS;
    for(int i=0;i<WXG_FRAME_MS_BINS;i++)into->bins[i]+=from->bins[i];
}
/* Frames shown per second of measured time. */
static inline double WXGFrameStatsFPS(const WXGFrameStats *s) {return s && s->totalMS>0.?s->frames*1000./s->totalMS:0.;}
/* Missed refreshes out of all the refreshes in the time (shown + missed). */
static inline double WXGFrameStatsDropRate(const WXGFrameStats *s) {
    double all=s?(double)s->frames+(double)s->dropped:0.;
    return all>0.?s->dropped/all:0.;
}
/* Hitch time per second, ms/s (under 5 good, 5-10 noticeable, over 10 bad). */
static inline double WXGFrameStatsHitchRatio(const WXGFrameStats *s) {return s && s->totalMS>0.?s->hitchMS/(s->totalMS/1000.):0.;}
/* The plugin's main-thread time per second, ms/s. */
static inline double WXGFrameStatsPluginRatio(const WXGFrameStats *s) {return s && s->totalMS>0.?s->pluginMS/(s->totalMS/1000.):0.;}
/* The p-quantile of the intervals (0 < p <= 1), as the upper edge of its 1 ms
   bin: p of the frames took less than this. The last bin answers the worst. */
static inline double WXGFrameStatsPercentile(const WXGFrameStats *s,double p) {
    if(!s || !s->frames || !(p>0.))return 0.;
    if(p>1.)p=1.;
    double target=p*s->frames,cumulative=0.;
    for(int i=0;i<WXG_FRAME_MS_BINS;i++) {
        cumulative+=s->bins[i];
        if(s->bins[i] && cumulative>=target-1e-9)return i==WXG_FRAME_MS_BINS-1?s->worstMS:(double)(i+1);
    }
    return s->worstMS;
}
/* The expected interval for a callback: the display link's own frame
   (target - timestamp), else the screen's fastest refresh. */
static inline double WXGFrameExpectedMS(double targetMinusTimestampMS,int maximumFPS) {
    if(targetMinusTimestampMS>2. && targetMinusTimestampMS<60. && isfinite(targetMinusTimestampMS))return targetMinusTimestampMS;
    return 1000./(maximumFPS>=30?maximumFPS:60);
}
#endif
