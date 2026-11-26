#ifndef WXGMeMetaball_h
#define WXGMeMetaball_h
/* FIX118 A: the 我 page's header (user, 11-04: Telegram's profile page with
   expo-scroll-metaball's effect: the avatar, centred, as the page is scrolled
   up shrinks, blurs, darkens and melts into the Dynamic Island; pulled down it
   opens into a banner whose lower edge moves like a liquid). Pure C: the
   phones' cut-outs, the layout and the motion, tested in
   Tests/MeMetaballTests.c; WXGMeHeader.m draws it.

   The cut-outs are Telegram-iOS's measurements (DeviceMetrics.cutoutFrame: the
   sensor housing of each model, in points of the phone's own screen), looked
   up by the model identifier; a phone not in the table is guessed from its
   top safe area (59 pt or more: an island, 44-50: a notch, less: none). */
#include <math.h>
#include <string.h>

typedef enum {WXGCutoutNone=0,WXGCutoutNotch=1,WXGCutoutIsland=2} WXGCutoutKind;
typedef struct {double x,y,w,h;WXGCutoutKind kind;int known;} WXGCutout;

typedef struct {const char *models;double screenWidth,w,h,top;WXGCutoutKind kind;} WXGCutoutProfile;
static const WXGCutoutProfile WXGCutoutProfiles[]={
    // the X / XS / 11 Pro
    {",iPhone10,3,iPhone10,6,iPhone11,2,iPhone12,3,",375,223,30,0,WXGCutoutNotch},
    // the XS Max / 11 Pro Max
    {",iPhone11,4,iPhone11,6,iPhone12,5,",414,223,30,0,WXGCutoutNotch},
    // the XR / 11
    {",iPhone11,8,iPhone12,1,",414,246,33,0,WXGCutoutNotch},
    {",iPhone13,1,",375,242,34,0,WXGCutoutNotch},                              // 12 mini
    {",iPhone13,2,iPhone13,3,",390,222,32,0,WXGCutoutNotch},                   // 12 / 12 Pro
    {",iPhone13,4,",428,222,32,0,WXGCutoutNotch},                              // 12 Pro Max
    {",iPhone14,4,",375,189,38,0,WXGCutoutNotch},                              // 13 mini
    {",iPhone14,5,iPhone14,7,iPhone17,5,iPhone18,5,",390,176,34,0,WXGCutoutNotch},   // 13 / 14 / 16e / 17e
    {",iPhone14,2,",390,176,34,0,WXGCutoutNotch},                              // 13 Pro
    {",iPhone14,3,iPhone14,8,",428,176,34,0,WXGCutoutNotch},                   // 13 Pro Max / 14 Plus
    // 14 Pro / 15 / 15 Pro / 16
    {",iPhone15,2,iPhone15,4,iPhone16,1,iPhone17,3,",393,126,112.0/3,11,WXGCutoutIsland},
    // 14 Pro Max / 15 Plus / 15 Pro Max / 16 Plus
    {",iPhone15,3,iPhone15,5,iPhone16,2,iPhone17,4,",430,126,112.0/3,11,WXGCutoutIsland},
    {",iPhone17,1,iPhone18,1,iPhone18,3,",402,126,112.0/3,41.0/3,WXGCutoutIsland},   // 16 Pro / 17 Pro / 17
    {",iPhone17,2,iPhone18,2,",440,126,112.0/3,41.0/3,WXGCutoutIsland},            // 16 Pro Max / 17 Pro Max
    {",iPhone18,4,",420,126,112.0/3,59.0/3,WXGCutoutIsland},                      // Air
};
/* The cut-out on this phone, in its screen's points (a zoomed display scales
   the profile by the screen's width). */
static inline WXGCutout WXGCutoutFor(const char *model,double screenWidth,double safeTop) {
    WXGCutout c={0,0,0,0,WXGCutoutNone,0};
    if(model && *model) {
        char key[40];size_t n=strlen(model);
        if(n<sizeof key-2) {
            key[0]=',';memcpy(key+1,model,n);key[n+1]=',';key[n+2]=0;
            for(size_t i=0;i<sizeof WXGCutoutProfiles/sizeof *WXGCutoutProfiles;i++) {
                const WXGCutoutProfile *p=&WXGCutoutProfiles[i];
                if(!strstr(p->models,key))continue;
                double f=screenWidth>1?screenWidth/p->screenWidth:1;
                c.w=p->w*f;c.h=p->h*f;c.y=p->top*f;c.x=(screenWidth-c.w)*.5;c.kind=p->kind;c.known=1;
                return c;
            }
        }
    }
    if(safeTop>=59){c.w=126;c.h=112.0/3;c.y=fmax(safeTop-48,8);c.x=(screenWidth-c.w)*.5;c.kind=WXGCutoutIsland;}
    else if(safeTop>=40){c.w=fmin(223,screenWidth*.54);c.h=30;c.y=0;c.x=(screenWidth-c.w)*.5;c.kind=WXGCutoutNotch;}
    return c;
}

/* The header laid out in the header's own coordinates (WeChat's header button:
   its top is 0, `height` tall): WeChat's two status buttons in a row near its
   bottom (inside it, so they take their own touches), the WeChat ID above
   them, the name above that, reaching up out of the header, and the avatar
   above the name. FIX118 D (user: "头像也能点进个人资料设置，所以直接删掉下面的
   那个列表里的个人资料"): no 个人资料 row (rowHeight 0). `shift` is how far the
   list moves down for it (the header's top at rest, in the window, minus
   where WeChat had it). */
typedef struct {
    double avatarCenterY,avatarRadius,nameCenterY,idCenterY,statusTop,bandTop,rowTop,rowHeight,shift;
} WXGMeLayout;
static inline WXGMeLayout WXGMeLayoutFor(double headerHeight,double safeTop,double nativeTop,double diameter) {
    WXGMeLayout l;
    if(diameter<60)diameter=60;
    if(diameter>140)diameter=140;
    l.avatarRadius=diameter*.5;
    l.statusTop=headerHeight-24-20;
    if(l.statusTop<42)l.statusTop=42;
    l.idCenterY=l.statusTop-18;
    l.nameCenterY=l.idCenterY-28;
    l.avatarCenterY=l.nameCenterY-17-10-l.avatarRadius;
    l.rowHeight=0;l.rowTop=headerHeight;l.bandTop=headerHeight;
    // the avatar's top 14 pt under the top safe area
    l.shift=(safeTop+14+l.avatarRadius)-(nativeTop+l.avatarCenterY);
    if(l.shift<0)l.shift=0;
    return l;
}

/* The motion at `travel` points of scrolling (0 at rest, up positive; down,
   with the banner on, negative). `collapse` is how far the avatar goes to the
   cut-out's centre. */
typedef struct {
    double centerY,radius,darkness,blur,goo,presence,stretch,tip,blend,expand,fade;
} WXGMetaballPose;
static inline double WXGMBLerp(double x,double x0,double x1,double y0,double y1) {
    if(x1==x0)return x<=x0?y0:y1;
    double u=(x-x0)/(x1-x0);if(u<0)u=0;if(u>1)u=1;
    return y0+(y1-y0)*u;
}
static inline double WXGMBStops(double x,const double *xs,const double *ys,int n) {
    if(x<=xs[0])return ys[0];
    for(int i=1;i<n;i++)if(x<=xs[i])return WXGMBLerp(x,xs[i-1],xs[i],ys[i-1],ys[i]);
    return ys[n-1];
}
/* `merge`: the avatar melts into a cut-out (an island; a notch when the user
   has chosen so); otherwise it only shrinks and fades towards it (Telegram
   on a notched phone). `bannerPull`: how far a pull opens the banner fully. */
static inline WXGMetaballPose WXGMetaballPoseAt(double travel,double collapse,double restCenterY,double restRadius,
                                                double cutoutBottom,int merge,double bannerPull) {
    WXGMetaballPose p;memset(&p,0,sizeof p);
    double C=collapse>1?collapse:1;
    double t=travel;
    // the avatar moves with the page; at the cut-out it stays there
    p.centerY=restCenterY-(t<C?t:C);
    {double xs[3]={0,C*.5,C},ys[3]={restRadius,restRadius*.62,0};p.radius=t<0?restRadius:WXGMBStops(t,xs,ys,3);}
    p.blur=WXGMBLerp(t,C*.08,C*.5,0,24);
    p.expand=t<0 && bannerPull>1?WXGMBLerp(-t,0,bannerPull,0,1):0;
    double gate=1-p.expand;
    if(merge) {
        p.darkness=WXGMBLerp(t,C*.6,C*.95,0,1);
        {double xs[4]={0,C*.3,C*.78,C},ys[4]={16,50,50,0};p.goo=WXGMBStops(t,xs,ys,4)*gate;}
        // (the drawn cut-out grows from its centre only as the avatar nears it: at rest nothing is drawn
        // over the real one, so a cut-out a little off never shows a black edge)
        p.presence=WXGMBLerp(t,C*.15,C*.5,0,1);
        p.blend=WXGMBLerp(t,C*.05,C*.8,0,1);
        p.fade=1;
    }else {
        p.darkness=0;p.goo=0;p.presence=0;p.blend=0;
        p.fade=1-WXGMBLerp(t,C*.4,C*.9,0,1);
    }
    p.tip=p.radius*.22;
    double base=p.radius-p.tip,full=fmax(base,p.centerY-cutoutBottom);
    double reach=merge?WXGMBLerp(t,C*.22,C*.4,0,1):0;
    p.stretch=base+(full-base)*reach;
    if(t<0){p.blur=0;p.darkness=0;p.blend=0;p.stretch=base;}
    return p;
}

/* FIX119 B (user, 11-05, on the 16 Pro Max: "两个昵称同时存在 … 你能不能去找
   Telegram 这个页面的处理逻辑 … 它分了段，不会乱跳"): Telegram's title collapse
   (PeerInfoHeaderNode: titleCollapseOffset = titleFrame.midY - statusBarHeight
   - titleLockOffset; titleOffset = -min(titleCollapseOffset, contentOffset);
   titleScale 1 -> 0.6, subtitleScale 1 -> 0.8, subtitle alpha 1 - fraction).
   One name: it goes up with the page until its centre reaches the bar's
   centre, shrinking on the way to the bar title's size, and stays there (it
   is the bar's title then); the ID under it shrinks a little, follows it and
   is gone before it locks. `naturalY`: where the page has the name now (in
   the window), `travelUp`: how far the page is scrolled up (0 or less: at
   rest or pulled down, the name where the page has it, full size). */
typedef struct {double titleY,titleScale,idY,idScale,idAlpha,fraction,collapse;int locked;} WXGMeTitlePose;
static inline WXGMeTitlePose WXGMeTitlePoseAt(double naturalY,double travelUp,double lockY,double idGap,double lockScale) {
    WXGMeTitlePose p;
    double up=travelUp>0?travelUp:0;
    double restY=naturalY+up;
    p.collapse=restY-lockY;if(p.collapse<1)p.collapse=1;
    double f=up/p.collapse;if(f>1)f=1;
    p.fraction=f;
    p.titleY=naturalY>lockY?naturalY:lockY;
    if(up<=0)p.titleY=naturalY;
    p.titleScale=1+(lockScale-1)*f;
    p.idScale=1-.2*f;
    p.idY=p.titleY+idGap*(1-.3*f);
    double a=f/.7;if(a>1)a=1;
    p.idAlpha=1-a*a*(3-2*a);
    p.locked=up>=p.collapse-.5;
    return p;
}
/* The bar's background, as Telegram's (a step, not a fade that follows the
   finger): on once the title has locked, off again only a few points below
   (no flicker at the edge); the caller animates the change. */
static inline int WXGMeBandOn(int wasOn,double travelUp,double titleCollapse) {
    if(travelUp>=titleCollapse-1)return 1;
    if(travelUp<titleCollapse-8)return 0;
    return wasOn;
}
/* The metal layer only as tall as what it draws (FIX119 B: it was the whole
   window, a full-screen layer blended on every frame): down to `maxY`, in
   steps of 96 pt (its drawables are not made anew on every frame), never
   more than the window. */
static inline double WXGMeCanvasHeight(double maxY,double windowHeight) {
    double h=ceil((maxY+8)/96)*96;
    if(h<96)h=96;
    if(h>windowHeight)h=windowHeight;
    return h;
}
#endif
