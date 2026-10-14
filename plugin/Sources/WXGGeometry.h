#ifndef WXG_GEOMETRY_H
#define WXG_GEOMETRY_H
#include <math.h>
/* Screenshot reference: 1320 px / 3 = 440 pt. All horizontal positions are
   recomputed in the current safe width; no device-name or notch constants. */
typedef struct { double x,y,w,h; } WXGRect;
typedef struct { double scale,edge,gap,button,icon,inputButton,inputGap,inputEdge; } WXGMetrics;
static inline double WXGBound(double x,double a,double b) { return fmin(b,fmax(a,x)); }
static inline WXGMetrics WXGMeasure(double usableWidth,double multiplier) {
    double s=WXGBound(usableWidth/440.0,.70,1.25)*WXGBound(multiplier,.85,1.20);
    return (WXGMetrics){s,20*s,fmax(8,10*s),fmax(36,44*s),22*s,fmax(36,40*s),12*s,28*s};
}
static inline double WXGCapsuleWidth(double textWidth,double iconWidth,double height,double padding,double limit) {
    return fmin(limit,fmax(height,ceil(textWidth+iconWidth+padding*2)));
}
static inline WXGRect WXGCenteredInk(double canvasW,double canvasH,double inkW,double inkH,double maximum) {
    double s=fmin(maximum/fmax(inkW,.01),maximum/fmax(inkH,.01));
    double w=inkW*s,h=inkH*s;
    return (WXGRect){(canvasW-w)*.5,(canvasH-h)*.5,w,h};
}
typedef struct { WXGRect plus,pill,mic,editor; } WXGInputGeometry;
static inline WXGInputGeometry WXGInputLayout(double width,double safeLeft,double safeRight,double centerY,
                                             double originalGrowHeight,double nativeTextHeight,double multiplier) {
    WXGMetrics m=WXGMeasure(width-safeLeft-safeRight,multiplier);
    double d=m.inputButton,extra=fmax(0,originalGrowHeight-40),h=d+extra;
    double x=safeLeft+m.inputEdge,pillX=x+d+m.inputGap;
    double pillW=fmax(100,width-safeRight-m.inputEdge-pillX);
    double y=centerY-h*.5,micD=d*.90;
    return (WXGInputGeometry){
        {x,centerY-d*.5,d,d},{pillX,y,pillW,h},
        {pillX+pillW-6*m.scale-micD,centerY-micD*.5,micD,micD},
        {pillX+14*m.scale,y+fmax(3,(h-nativeTextHeight)*.5),
         fmax(40,pillW-14*m.scale-6*m.scale-micD-4*m.scale),fmin(nativeTextHeight,h-6)}
    };
}
#endif
