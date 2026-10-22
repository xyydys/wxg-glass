#ifndef WXG_ELASTIC_MOTION_H
#define WXG_ELASTIC_MOTION_H
#include "WXGMotion.h"
#include "WXGOptics.h"
// Only the post-reveal elastic stretch. No activeScale, alpha crossfade,
// release-distance envelope, optical bevel, or replacement press spring.
typedef struct {double stretch,velocity,previousSpeed,acceleration;} WXGElasticMotion;
// FIX37 (user: stronger and easier to trigger, iOS 26 goes thinner than the
// bar): acceleration/braking react at lower rates, a larger stretch range.
// FIX39 (user: FIX37 reached the longest shape on any quick drag): speed maps
// proportionally (28% at 300 pt/s, 49% at 600, 67% at 1000, 89% at 2000) so
// the stretch follows the hand, and a calmer stretch spring.
#define WXG_ELASTIC_SPEED 900.
#define WXG_ELASTIC_GAIN .52
#define WXG_ELASTIC_MIN .70
#define WXG_ELASTIC_MAX 1.60
static inline void WXGElasticStep(WXGElasticMotion *s,double velocity,double dt) {
    dt=WXGClamp(dt,0,.064);if(dt<=0)return;
    double speed=fabs(velocity),a=(speed-s->previousSpeed)/dt;s->previousSpeed=speed;
    s->acceleration+=(a-s->acceleration)*fmin(1,dt/(dt+1./55.));
    double f=WXGClamp(1-exp(-speed/WXG_ELASTIC_SPEED),0,1);
    double accel=WXGClamp(s->acceleration/4200.,0,1),brake=WXGClamp(-s->acceleration/3000.,0,1);
    double drive=WXGClamp(f*(.85+.15*accel)-1.35*brake*fmax(.25,f),-.85,1);
    WXGSpring(&s->stretch,&s->velocity,log1p(WXG_ELASTIC_GAIN*drive),140,10.,dt);
    s->stretch=WXGClamp(s->stretch,log(WXG_ELASTIC_MIN),log(WXG_ELASTIC_MAX));
}
// FIX113 Y (user: while the lens stretches with the drag speed, the band
// above / below the bar inside it swings from almost nothing to fat): the
// share of the height change kept (1 as before, 0 the height never changes;
// the width still stretches).
static inline WXGDockGeometry WXGElasticLayoutLimited(float width,float height,float gap,float anchor,
        float press,float growth,float demoStretch,WXGElasticMotion motion,float barGrowth,float wrap,float heightShare);
static inline WXGDockGeometry WXGElasticLayout(float width,float height,float gap,float anchor,
        float press,float growth,float demoStretch,WXGElasticMotion motion,float barGrowth,float wrap) {
    return WXGElasticLayoutLimited(width,height,gap,anchor,press,growth,demoStretch,motion,barGrowth,wrap,1.f);
}
static inline WXGDockGeometry WXGElasticLayoutLimited(float width,float height,float gap,float anchor,
        float press,float growth,float demoStretch,WXGElasticMotion motion,float barGrowth,float wrap,float heightShare) {
    // Keep the first 65% of the original demo reveal unchanged. Gate both value
    // and slope smoothly; release is still entirely driven by the demo envelope.
    float t=WXGOClamp((press-.65f)/.35f,0,1),gate=t*t*(3-2*t);
    WXGDockGeometry g=WXGDockLayout(width,height,gap,anchor,press,growth,demoStretch*(1-gate),barGrowth,wrap);
    if(gate<=0)return g;
    float strain=(float)motion.stretch*gate,restHeight=g.lensHeight;
    g.lensWidth=WXG_MIN(g.lensWidth*expf(strain),g.barWidth+2*wrap);
    if(strain>0) {
        // Normalize the vertical contraction to the user's larger TEST9
        // resting lens: sustained fast travel approaches the bar's height.
        float compression=WXGOClamp((1-expf(-.78f*strain))/(1-expf(-.78f*log1pf((float)WXG_ELASTIC_GAIN*.85f))),0,gate);
        // Sustained fast travel now ends slightly thinner than the bar (90%).
        g.lensHeight+=(g.barHeight*.90f-g.lensHeight)*compression;
    }else g.lensHeight*=expf(-.78f*strain);
    g.lensHeight=restHeight+(g.lensHeight-restHeight)*WXGOClamp(heightShare,0.f,1.f);   // FIX113 Y
    g.lensHeight=WXG_MIN(g.lensHeight,height+2*(WXGCanvasPaddingY-4));
    float first=WXGSelectionCenter(width,gap,0),last=WXGSelectionCenter(width,gap,3);
    float position=WXGOClamp((anchor-first)/WXG_MAX(1.f,last-first),0,1);
    float edge=gap*g.scale*(1-WXGOClamp(press,0,1))-wrap*WXGOClamp(press,0,1);
    g.lensX=g.barX+edge+position*(g.barWidth-2*edge-g.lensWidth);g.lensY=(height-g.lensHeight)*.5f;
    return g;
}
#endif
