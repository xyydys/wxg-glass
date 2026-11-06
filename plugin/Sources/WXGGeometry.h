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
/* FIX114 M (user: a taller capsule under the avatar is for more room around
   the text, not larger text): the text's size is its own setting, whatever the
   height; only a capsule too low for it (the text over 0.62 of the height)
   shrinks it, in half points. */
static inline double WXGAvatarCapsuleTextSize(double wanted,double height) {
    return fmin(WXGBound(wanted,11,20),floor(fmax(height,0)*.62*2)/2);
}
/* FIX114 M: a title and a small symbol after it (iOS 26's chevron), centred
   together on `midX`: the text's centre and the symbol's left edge.
   FIX114 O (user: the capsule's two sides looked out of balance): iOS 26
   leaves less room after the chevron than before the text (measured 13.7 /
   11 pt): `bias` moves the pair that far right (half the difference of the
   two paddings; 0 = centred as M). */
typedef struct { double textMidX,symbolX; } WXGTrailingPlace;
static inline WXGTrailingPlace WXGTrailingLayoutBiased(double midX,double textWidth,double gap,double symbolWidth,double bias) {
    double shift=(gap+symbolWidth)*.5-bias;
    return (WXGTrailingPlace){midX-shift,midX-shift+textWidth*.5+gap};
}
static inline WXGTrailingPlace WXGTrailingLayout(double midX,double textWidth,double gap,double symbolWidth) {
    return WXGTrailingLayoutBiased(midX,textWidth,gap,symbolWidth,0);
}
/* FIX114 O: WeChat's own title-bar buttons of one side put in the slots the
   plugin's own row gives (WXGLocalGlass.m): the outermost glass `start` from
   the screen's side (safe area + 顶部按钮离屏幕两边), each next one a `gap`
   further in. Each button: its frame in the bar (any offset common to the
   side: a push moves them together), its glass in the button, its width; the
   outermost first. Where WeChat puts it once settled: the bar's side, its
   margin there, then the buttons' places relative to the outermost. Shift =
   slot less that (window points, x). */
typedef struct { double frameMin,frameMax,glassMin,glassMax,buttonWidth; } WXGNavSlotButton;
static inline void WXGNavSlotShifts(int left,const WXGNavSlotButton *b,int n,double barMin,double barMax,double margin,double start,double gap,double *shift) {
    double x=start;
    for(int i=0;i<n;i++) {
        double native=left?barMin+margin+(b[i].frameMin-b[0].frameMin)+b[i].glassMin
                          :barMax-margin-(b[0].frameMax-b[i].frameMax)-(b[i].buttonWidth-b[i].glassMax);
        shift[i]=x-native;
        double w=b[i].glassMax-b[i].glassMin;
        x+=left?w+gap:-(w+gap);
    }
}
static inline WXGRect WXGCenteredInk(double canvasW,double canvasH,double inkW,double inkH,double maximum) {
    double s=fmin(maximum/fmax(inkW,.01),maximum/fmax(inkH,.01));
    double w=inkW*s,h=inkH*s;
    return (WXGRect){(canvasW-w)*.5,(canvasH-h)*.5,w,h};
}
typedef struct { WXGRect plus,pill,mic,editor; } WXGInputGeometry;
/* FIX115 J (user: the two-ended bar's text capsule taller and shorter, the
   plus growing with it, adjustable): its single-line height, the plus' size,
   the distance from the screen's sides and from the plus to the capsule, in
   points at the reference width (scaled with it like every metric). A field
   below 0 (height / plus / gap) or edge below 0 = TEST9's own (40, the
   capsule's height, 12, 28); a plus of 0 = the capsule's height. The mic
   inside keeps its share of the height (0.9). */
typedef struct { double height,plus,edge,gap; } WXGInputSize;
static inline WXGInputSize WXGInputSizeTEST9(void) {return (WXGInputSize){-1,-1,-1,-1};}
static inline WXGInputGeometry WXGInputLayoutSized(double width,double safeLeft,double safeRight,double centerY,
                                                   double originalGrowHeight,double nativeTextHeight,double multiplier,WXGInputSize size) {
    WXGMetrics m=WXGMeasure(width-safeLeft-safeRight,multiplier);
    double d=size.height>0?fmax(28,size.height*m.scale):m.inputButton;
    double p=size.plus>0?fmax(24,size.plus*m.scale):d;
    double edge=size.edge>=0?size.edge*m.scale:m.inputEdge,gap=size.gap>=0?size.gap*m.scale:m.inputGap;
    double extra=fmax(0,originalGrowHeight-40),h=d+extra;
    double x=safeLeft+edge,pillX=x+p+gap;
    double pillW=fmax(100,width-safeRight-edge-pillX);
    double y=centerY-h*.5,micD=d*.90;
    return (WXGInputGeometry){
        {x,centerY-p*.5,p,p},{pillX,y,pillW,h},
        {pillX+pillW-6*m.scale-micD,centerY-micD*.5,micD,micD},
        {pillX+14*m.scale,y+fmax(3,(h-nativeTextHeight)*.5),
         fmax(40,pillW-14*m.scale-6*m.scale-micD-4*m.scale),fmin(nativeTextHeight,h-6)}
    };
}
static inline WXGInputGeometry WXGInputLayout(double width,double safeLeft,double safeRight,double centerY,
                                             double originalGrowHeight,double nativeTextHeight,double multiplier) {
    return WXGInputLayoutSized(width,safeLeft,safeRight,centerY,originalGrowHeight,nativeTextHeight,multiplier,WXGInputSizeTEST9());
}
/* FIX115 J: how far the text starts inside a capsule taller than TEST9's:
   half the extra height (its round end is that much wider), never less than
   TEST9's own place. */
static inline double WXGInputTextInset(double capsuleHeight,double test9Height) {
    return fmax(0,(capsuleHeight-test9Height)*.5);
}
#endif
