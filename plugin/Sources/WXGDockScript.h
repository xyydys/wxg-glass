#ifndef WXGDockScript_h
#define WXGDockScript_h
#include <math.h>
#include "WXGDockSystem.h"
/* FIX95: the tap animation is the real lens (the one a drag summons: Metal,
   refraction, dispersion, the bar under it), driven frame by frame along the
   curves the render-server tap animation used (FIX43 timing, FIX44 / FIX88
   lift and drop): where its anchor is (the glide's cubic-bezier) and how far it
   is pressed (keyframes, an ease per segment) at any time. Pure C (tests).
   FIX98 (user: the pill went clear the instant it was touched and coloured the
   instant it landed; too fast): the selection colour has its own track, fading
   out over the move and back over the drop; the move is slower (a scale on the
   FIX43 timing) and the drop has its own, longer duration, starting a little
   before the lens arrives and finishing after it.
   FIX99 (user: going clear and coming back took longer than the move, it felt
   unnatural): the pill turns into the lens over the first 40% of the move (a
   setting; lift and colour together, was 55% / 65%), the drop is shorter
   (0.16 s) and starts 70% of it before the lens arrives, so it is down 0.05 s
   after: the whole colour change now fits the move. */
static inline double WXGScriptClamp(double x,double a,double b) {return x<a?a:(x>b?b:x);}
// A cubic-bezier ease (control points x1, y1, x2, y2) at x in 0..1.
static inline double WXGScriptBezier(double x,double x1,double y1,double x2,double y2) {
    x=WXGScriptClamp(x,0,1);double t=x;
    for(int i=0;i<10;i++) {
        double cx=3*x1*t*(1-t)*(1-t)+3*x2*t*t*(1-t)+t*t*t-x;
        double dx=3*x1*(1-t)*(1-t)+6*(x2-x1)*t*(1-t)+3*(1-x2)*t*t;
        if(fabs(cx)<1e-7 || fabs(dx)<1e-9)break;
        t=WXGScriptClamp(t-cx/dx,0,1);
    }
    return 3*y1*t*(1-t)*(1-t)+3*y2*t*t*(1-t)+t*t*t;
}
enum {WXGScriptMaxKeys=6};
typedef struct {
    int count;
    double t[WXGScriptMaxKeys],v[WXGScriptMaxKeys];   // absolute times (increasing), values
    double ease[WXGScriptMaxKeys][4];                 // the ease of the segment ending at key i
} WXGScriptTrack;
typedef struct {
    int phase;                     // 0 none, 1 glide (finger down), 2 landing (released)
    long index;                    // the tab it goes to
    double moveStart,moveDuration,moveFrom,moveTo;   // the lens's anchor (x)
    double moveResponse,moveDamping;                 // FIX127: > 0, the move runs on the system's spring (WXGDockSpringEase), not the bezier
    WXGScriptTrack press;          // how far it is lifted (until the drop, in phase 2)
    WXGScriptTrack select;         // FIX98: the selection colour (1 the resting pill, 0 the clear lens)
    double planEnd;                // the move arrives
    double dropStart,land,end;     // phase 2: the drop runs dropStart..land; the script is over at end
} WXGDockScript;
// The lift / drop / colour curves (FIX44 lift and drop; the colour in-out).
// FIX99: the lift and the colour share one span (the caller's `share` of the
// move, 胶囊变透镜); the drop starts 70% of itself before the lens arrives.
#define WXGScriptDropLead .70      // of the drop: it starts this long before the lens arrives
#define WXGScriptSettle .05        // down, held this long before the script ends
static inline void WXGScriptTrackAdd(WXGScriptTrack *k,double t,double v,double x1,double y1,double x2,double y2) {
    if(k->count>=WXGScriptMaxKeys)return;
    if(k->count && t<k->t[k->count-1])t=k->t[k->count-1];
    int i=k->count++;k->t[i]=t;k->v[i]=v;k->ease[i][0]=x1;k->ease[i][1]=y1;k->ease[i][2]=x2;k->ease[i][3]=y2;
}
static inline double WXGScriptTrackValue(const WXGScriptTrack *k,double time) {
    if(k->count<=0)return 0;
    if(time<=k->t[0])return k->v[0];
    for(int i=1;i<k->count;i++) {
        if(time>k->t[i])continue;
        double span=k->t[i]-k->t[i-1];
        double u=span>1e-9?(time-k->t[i-1])/span:1;
        double e=WXGScriptBezier(u,k->ease[i][0],k->ease[i][1],k->ease[i][2],k->ease[i][3]);
        return k->v[i-1]+(k->v[i]-k->v[i-1])*e;
    }
    return k->v[k->count-1];
}
static inline double WXGScriptMoveValue(const WXGDockScript *s,double time) {
    if(!(s->moveDuration>1e-6))return time>=s->moveStart?s->moveTo:s->moveFrom;
    double u=(time-s->moveStart)/s->moveDuration;
    if(s->moveResponse>0)return s->moveFrom+(s->moveTo-s->moveFrom)*WXGDockSpringEase(u,s->moveResponse,s->moveDamping);   // FIX127
    return s->moveFrom+(s->moveTo-s->moveFrom)*WXGScriptBezier(u,.40,0,.30,1);
}
// The drop's progress at `time` (0 before it, 1 once down), with an ease.
static inline double WXGScriptDropProgress(const WXGDockScript *s,double time,double x1,double y1,double x2,double y2) {
    if(s->phase!=2 || time<=s->dropStart)return 0;
    if(time>=s->land)return 1;
    return WXGScriptBezier((time-s->dropStart)/(s->land-s->dropStart),x1,y1,x2,y2);
}
// FIX98: lifted: the track until the drop; then from where it was to 0.
static inline double WXGScriptPressValue(const WXGDockScript *s,double time) {
    if(s->phase!=2 || time<=s->dropStart)return WXGScriptTrackValue(&s->press,time);
    double from=WXGScriptTrackValue(&s->press,s->dropStart);
    return from*(1-WXGScriptDropProgress(s,time,.45,0,.35,1));
}
// FIX98: the colour: the track until the drop; then from where it was back to 1.
static inline double WXGScriptSelectValue(const WXGDockScript *s,double time) {
    if(s->phase!=2 || time<=s->dropStart)return WXGScriptTrackValue(&s->select,time);
    double from=WXGScriptTrackValue(&s->select,s->dropStart);
    return from+(1-from)*WXGScriptDropProgress(s,time,.42,0,.58,1);
}
// Value and rate (per second, central difference) at `time`.
static inline double WXGScriptTrackAt(const WXGScriptTrack *k,double time,double *rate) {
    const double h=1./480;
    if(rate)*rate=(WXGScriptTrackValue(k,time+h)-WXGScriptTrackValue(k,time-h))/(2*h);
    return WXGScriptTrackValue(k,time);
}
static inline double WXGScriptMoveAt(const WXGDockScript *s,double time,double *rate) {
    const double h=1./480;
    if(rate)*rate=(WXGScriptMoveValue(s,time+h)-WXGScriptMoveValue(s,time-h))/(2*h);
    return WXGScriptMoveValue(s,time);
}
static inline double WXGScriptPressAt(const WXGDockScript *s,double time,double *rate) {
    const double h=1./480;
    if(rate)*rate=(WXGScriptPressValue(s,time+h)-WXGScriptPressValue(s,time-h))/(2*h);
    return WXGScriptPressValue(s,time);
}
/* Touch-down on another tab (FIX43 / FIX44): the glide over `duration` (the
   caller's FIX43 time x the scale), the press up to the lift (0.9, or more if
   already pressed) and the colour from `s0` (1 at rest) to clear, both over
   the first `share` of it (FIX99), then held while the finger stays down. */
static inline WXGDockScript WXGScriptGlide(double now,double from,double to,double duration,double p0,double s0,long index,double share) {
    WXGDockScript s={0};
    s.phase=1;s.index=index;s.moveStart=now;s.moveDuration=duration>.05?duration:.05;s.moveFrom=from;s.moveTo=to;
    share=WXGScriptClamp(share,.15,.90);
    double lifted=p0>.90?p0:.90;
    WXGScriptTrackAdd(&s.press,now,p0,0,0,1,1);
    WXGScriptTrackAdd(&s.press,now+s.moveDuration*share,lifted,.42,0,.58,1);
    WXGScriptTrackAdd(&s.press,now+s.moveDuration,lifted,0,0,1,1);
    s0=WXGScriptClamp(s0,0,1);
    WXGScriptTrackAdd(&s.select,now,s0,0,0,1,1);
    WXGScriptTrackAdd(&s.select,now+s.moveDuration*share,0,.42,0,.58,1);
    s.planEnd=now+s.moveDuration;s.dropStart=s.land=s.end=0;
    return s;
}
/* Release on the glide's tab (FIX44 dropTravel): the glide keeps going; the
   drop (`drop` s, FIX98) starts 70% of it before the lens arrives (or now, if
   released later), so it is down 30% of it after; at least 0.1 s from now. */
static inline void WXGScriptDrop(WXGDockScript *s,double now,double drop) {
    drop=WXGScriptClamp(drop,.06,1.5);
    double dropStart=s->planEnd-drop*WXGScriptDropLead;
    if(dropStart<now)dropStart=now;
    double land=dropStart+drop;
    if(land<now+.10)land=now+.10;
    s->phase=2;s->dropStart=dropStart;s->land=land;s->end=land+WXGScriptSettle;
}
/* Release elsewhere (a drag that ends on another tab, a glide not on its tab
   any more; FIX43 / FIX88 beginTravelToIndex): the move (nearly distance-
   independent x the FIX98 scale, a running glide's plan honoured), lifted on
   the way if it goes at least half a tab (the colour clearing as it lifts),
   then the drop as above. `slot`: one tab's distance. */
/* FIX127: `fresh` > 0: a move that follows no running plan lasts this long
   (the system's spring: WXGDockSpringDuration) instead of the FIX43 time. */
static inline WXGDockScript WXGScriptTravelTimed(double now,double from,double to,double slot,double p0,double s0,double planEnd,long index,
                                                 double scale,double drop,double share,double fresh) {
    WXGDockScript s={0};
    drop=WXGScriptClamp(drop,.06,1.5);scale=WXGScriptClamp(scale,.3,4);share=WXGScriptClamp(share,.15,.90);
    double remaining=fabs(to-from)/(slot>1?slot:1);
    double own=fresh>0?fresh:.27*(.85+.05*(remaining<3?remaining:3))*scale;
    double move=remaining<.05?0:(planEnd>now?(planEnd-now>.12?planEnd-now:.12):own);
    double lifted=remaining>=.5?(p0>.90?p0:.90):p0;
    int lifts=move>0 && lifted>p0+1e-6;
    s0=WXGScriptClamp(s0,0,1);
    s.phase=2;s.index=index;s.moveStart=now;s.moveDuration=move;s.moveFrom=from;s.moveTo=to;s.planEnd=now+move;
    WXGScriptTrackAdd(&s.press,now,p0,0,0,1,1);
    WXGScriptTrackAdd(&s.select,now,s0,0,0,1,1);
    if(lifts) {
        WXGScriptTrackAdd(&s.press,now+move*share,lifted,.42,0,.58,1);
        WXGScriptTrackAdd(&s.select,now+move*share,0,.42,0,.58,1);
    }
    double dropStart=move>0?now+move-drop*WXGScriptDropLead:now;
    if(lifts && dropStart<now+move*share+.02)dropStart=now+move*share+.02;
    if(dropStart<now)dropStart=now;
    s.dropStart=dropStart;s.land=dropStart+drop;
    if(s.land<now+move)s.land=now+move;
    s.end=s.land+WXGScriptSettle;
    return s;
}
static inline WXGDockScript WXGScriptTravel(double now,double from,double to,double slot,double p0,double s0,double planEnd,long index,
                                            double scale,double drop,double share) {
    return WXGScriptTravelTimed(now,from,to,slot,p0,s0,planEnd,index,scale,drop,share,0);
}
/* FIX127: the move on the system's spring (response s, damping ratio)
   instead of the bezier; its duration is the caller's (WXGDockSpringDuration
   for a move from rest). */
static inline void WXGScriptUseSpring(WXGDockScript *s,double response,double damping) {
    s->moveResponse=response>0?response:0;s->moveDamping=damping;
}
/* FIX127 (iOS 26: the lens stays lifted ~0.18 s after the finger leaves,
   then drops): a landing's drop not before `now` + `hang`; the lift and the
   colour hold where they are until then. */
static inline void WXGScriptHang(WXGDockScript *s,double now,double hang) {
    if(s->phase!=2 || !(hang>0))return;
    double by=now+hang-s->dropStart;
    if(!(by>0))return;
    s->dropStart+=by;s->land+=by;s->end+=by;
}
/* FIX98: whether WeChat's tab switch still waits (the host asks). `moment`
   0: not at all (it switches at the release, the lens carries on), 1: until
   the lens has nearly arrived (80% of its move: the drop then carries on),
   2: until it is down (FIX95). A finger still on a glide always holds it. */
static inline int WXGScriptHoldsSwitch(const WXGDockScript *s,double now,int moment) {
    if(s->phase==1)return 1;
    if(s->phase!=2 || moment<=0)return 0;
    if(moment==1)return now<s->moveStart+s->moveDuration*.80;
    return now<s->land;
}
/* FIX98: the animation clock: real time, but one step never more than `cap`
   (WeChat's tab switch stalls the main thread 0.1-0.3 s: the lens then pauses
   and carries on from where it was instead of jumping ahead). The cap is
   above a 30 fps frame, so only stalls are cut, never a slow but steady run. */
#define WXGScriptClockCap (1./24)
static inline double WXGScriptClockStep(double clock,double lastReal,double real,double cap) {
    double d=real-lastReal;
    if(!(d>0))d=0;
    if(d>cap)d=cap;
    return clock+d;
}
/* FIX100: every time in the script later by `by` s (WeChat's switch held the
   main thread that long: the lens then carries on from where it stopped). */
static inline void WXGScriptShift(WXGDockScript *s,double by) {
    if(!s->phase || !(by>0))return;
    s->moveStart+=by;s->planEnd+=by;
    if(s->dropStart>0)s->dropStart+=by;
    if(s->land>0)s->land+=by;
    if(s->end>0)s->end+=by;
    for(int i=0;i<s->press.count;i++)s->press.t[i]+=by;
    for(int i=0;i<s->select.count;i++)s->select.t[i]+=by;
}
/* FIX102: every time point T of the script to pivot + (T - pivot) x f: the
   same curve, f times as long from `pivot` on (f < 1 catches up after a
   pause). Values are unchanged at the pivot. */
static inline void WXGScriptScaleTime(WXGDockScript *s,double pivot,double f) {
    if(!s->phase || !(f>0) || f==1)return;
#define WXG_SCALE_T(x) ((x)=pivot+((x)-pivot)*f)
    WXG_SCALE_T(s->moveStart);s->moveDuration*=f;WXG_SCALE_T(s->planEnd);
    if(s->dropStart>0)WXG_SCALE_T(s->dropStart);
    if(s->land>0)WXG_SCALE_T(s->land);
    if(s->end>0)WXG_SCALE_T(s->end);
    for(int i=0;i<s->press.count;i++)WXG_SCALE_T(s->press.t[i]);
    for(int i=0;i<s->select.count;i++)WXG_SCALE_T(s->select.t[i]);
#undef WXG_SCALE_T
}
/* FIX102: after a pause of `pause` s (WeChat's switch), what is left from
   `now` runs faster by 60% of the pause, at most a quarter of it, so the tap
   still ends close to when it would have. Returns the factor used. */
static inline double WXGScriptCatchUp(WXGDockScript *s,double now,double pause) {
    if(!s->phase || !(pause>.01))return 1;
    double end=s->phase==2?s->end:s->planEnd,remaining=end-now;
    if(!(remaining>.05))return 1;
    double cut=pause*.6<remaining*.25?pause*.6:remaining*.25;
    double f=(remaining-cut)/remaining;
    WXGScriptScaleTime(s,now,f);
    return f;
}
/* FIX101: after a switch the lens waits for calm: a frame on time (within
   1.6 x the display's frame, 22 ms at least) counts, a late one starts the
   count again; it waits until three in a row, 0.6 s at most, or past that
   until one on time (not straight after a long frame), 1.2 s at most.
   Returns whether it still waits. */
static inline int WXGScriptCalmWait(int *calmFrames,double interval,double nominal,double waited) {
    if(interval>0)*calmFrames=interval<=(nominal*1.6>.022?nominal*1.6:.022)?*calmFrames+1:0;
    return *calmFrames<3 && (waited<.6 || (*calmFrames<1 && waited<1.2));
}
/* FIX99 (user: the first taps after a cold start were sluggish; WeChat is busy
   then and FIX98 capped every slow frame, so the lens ran in slow motion):
   capped only around a tab switch this dock forwarded (`switchAt`, real time:
   from just before it to 0.8 s after), never more than 0.5 s behind real time;
   any other slow frame runs on real time (on time, if less smooth).
   FIX100: the step across the switch (WeChat's own work, the stall) counts one
   60 Hz frame: the lens pauses and goes on; the busy frames after it, up to
   0.8 s, at most 1/30 s each (a 30 fps frame is not cut). */
#define WXGScriptClockMaxLag .50
#define WXGScriptSwitchCap (1./60)
#define WXGScriptAfterSwitchCap (1./30)
static inline double WXGScriptClockAdvance(double clock,double lastReal,double real,double switchAt) {
    int across=switchAt>0 && lastReal<=switchAt+.02 && real>switchAt;
    int nearSwitch=switchAt>0 && real>=switchAt-.02 && lastReal<=switchAt+.80;
    double next=WXGScriptClockStep(clock,lastReal,real,across?WXGScriptSwitchCap:nearSwitch?WXGScriptAfterSwitchCap:1e9);
    if(real-next>WXGScriptClockMaxLag)next=real-WXGScriptClockMaxLag;
    return next<clock?clock:next;
}
#endif
