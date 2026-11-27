#ifndef WXG_EDGE_FADE_MATH_H
#define WXG_EDGE_FADE_MATH_H
#include <math.h>
/* FIX64: the page edge fade and edge blur (WXGEdgeFade.m).
   Fade, from the author's WeChatFade 1.1: the page's list is masked by a
   vertical gradient of 129 evenly spaced stops. Near the top the alpha is
   smoothstep(y / top), near the bottom smoothstep((height - y) / bottom), the
   smaller of the two where they overlap; each band is at most the list's
   height, a band under 0.5 pt is off.
   Blur, from the shared edge-effect project (Telegram's EdgeEffect table): a
   variable blur whose strength falls from the edge to the band's inner end
   along 90 stops, alpha k / 255 at location n / 287 (the table's exact
   values), normalized so the edge is 1. */
#define WXG_EDGE_FADE_STOPS 129

static inline float WXGEdgeFadeSmooth(float v) {
    float t=v<0.f?0.f:v>1.f?1.f:v;
    return t*t*(3.f-2.f*t);
}
/* Mask alpha at y (0 = the list's top edge) for a list `height` tall. */
static inline float WXGEdgeFadeAlpha(float y,float height,float top,float bottom) {
    float h=height>1.f?height:1.f,a=1.f;
    if(top>h)top=h;
    if(bottom>h)bottom=h;
    if(top>.5f && y<top) {
        float s=WXGEdgeFadeSmooth(y/top);
        if(s<a)a=s;
    }
    if(bottom>.5f && y>h-bottom) {
        float s=WXGEdgeFadeSmooth((h-y)/bottom);
        if(s<a)a=s;
    }
    return a;
}
/* Complementary foreground cover, expressed in the list viewport's coordinates. */
static inline float WXGEdgeCoverAlpha(float y,float height,float top,float bottom,int nativeTopBar) {
    if(y<0.f || y>height)return 0.f;
    return 1.f-WXGEdgeFadeAlpha(y,height,nativeTopBar?0.f:top,bottom);
}
/* Blur strength at u (0 = the screen edge, 1 = the band's inner end): 1 .. 0,
   linear between the table's stops (as the shared project's CGGradient). */
static inline float WXGEdgeBlurStrength(float u) {
    static const unsigned char alpha255[90]={
        216,215,214,213,212,211,210,209,208,207,206,205,204,203,202,201,200,199,198,197,196,195,194,193,192,191,190,189,188,187,
        186,185,184,183,182,181,179,177,175,173,171,168,166,164,161,159,157,154,152,150,147,144,141,138,135,132,129,126,124,121,
        118,116,113,110,107,105,102,99,96,93,90,87,84,81,78,75,72,69,66,62,59,55,51,46,41,36,30,23,12,0};
    static const unsigned short location287[90]={
        0,6,17,25,31,35,38,41,44,46,49,52,55,58,60,61,63,65,67,68,70,71,73,74,75,77,78,79,81,82,
        83,84,85,86,87,88,90,92,94,96,98,100,102,104,106,108,109,111,113,114,116,118,120,122,124,126,128,130,131,133,
        135,136,138,140,142,143,145,147,149,151,153,155,157,159,161,163,165,167,169,172,174,177,180,184,189,194,200,209,227,287};
    if(!(u>0.f))return 1.f;
    if(u>=1.f)return 0.f;
    float p=u*287.f;
    for(int i=1;i<90;i++) {
        float a=location287[i-1],b=location287[i];
        if(p<=b) {
            float t=b>a?(p-a)/(b-a):1.f;
            return (alpha255[i-1]+(alpha255[i]-alpha255[i-1])*t)/216.f;
        }
    }
    return 0.f;
}
/* FIX67: how far WeChat's mini-program panel (pull the chat list down) is
   open, 0 .. 1, from where the panel's bottom edge is on screen as a fraction
   of the window's height: at rest it is under the navigation bar (88 / 896 =
   0.1), open near the bottom (0.93). A small pull (up to about 70 pt) is 0. */
static inline float WXGHomePanelProgress(float bottomFraction) {
    return WXGEdgeFadeSmooth((bottomFraction-.18f)/(.42f-.18f));
}
/* A band of the list, `extent` pt from its edge, clamped to the list. */
static inline float WXGEdgeBand(float extent,float height) {
    if(!(extent>.5f) || !(height>0.f))return 0.f;
    return extent<height?extent:height;
}
#endif
