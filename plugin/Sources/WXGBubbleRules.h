#ifndef WXG_BUBBLE_RULES_H
#define WXG_BUBBLE_RULES_H
#include <math.h>
/* FIX82: the liquid chat bubble's shape (the "无尾巴单行圆角" style of the
   user's MixBubble): WeChat's text bubble body without its tail, every
   corner the radius of a one-line bubble (half its height), so a one-line
   bubble is a capsule and a taller one keeps that same radius.

   The one-line height is read from WeChat's own bubbles: a body between 34
   and 59 pt tall is one line (40 pt at the standard text size, 48 / 56 with
   larger text, two lines start around 60). The reference is the smallest
   such body on screen, never below 40 pt. */
#define WXG_BUBBLE_REFERENCE 40.0
static inline int WXGBubbleOneLine(double height) {return height>=34 && height<59;}
static inline double WXGBubbleReference(double observed) {return observed>0?fmax(WXG_BUBBLE_REFERENCE,observed):WXG_BUBBLE_REFERENCE;}
static inline double WXGBubbleRadius(double width,double height,double observed) {
    if(!(width>0) || !(height>0))return 0;
    return fmin(WXGBubbleReference(observed)*.5,fmin(width,height)*.5);
}
/* Incoming bubbles' images reach left past the body (their tail): without a
   view model, an image starting at x >= 0 in the body is an outgoing one. */
static inline int WXGBubbleOutgoingFromImage(double imageMinX) {return imageMinX>=-.5;}
/* Physical fragments are already known to belong to the same message at
   this point. Theme/translation layouts can give them different widths. */
typedef struct {double x,y,w,h;} WXGBubbleBox;
/* Classify a lower native text renderer from its actual bounds. Replacement
   fonts can make the original renderer extend a few points below its skin. */
static inline int WXGBubbleTextBelowSkin(WXGBubbleBox skin,WXGBubbleBox text) {
    if(!(skin.w>0 && skin.h>0 && text.w>1 && text.h>1) ||
       text.x>=skin.x+skin.w || text.x+text.w<=skin.x)return 0;
    double bottom=skin.y+skin.h;
    double shared=fmax(0,fmin(bottom,text.y+text.h)-fmax(skin.y,text.y));
    double tolerance=fmin(18,fmax(4,text.h*.12));
    return shared<.55*text.h && text.y>=bottom-tolerance && text.y+.5*text.h>bottom+1.;
}
static inline int WXGBubbleAdjacentBoxes(WXGBubbleBox a,WXGBubbleBox b,int provenFamilyRows) {
    if(!(a.w>0 && a.h>0 && b.w>0 && b.h>0))return 0;
    double gap=b.y-(a.y+a.h);
    if(provenFamilyRows) {
        double overlap=fmin(a.x+a.w,b.x+b.w)-fmax(a.x,b.x);
        return gap>=-14 && gap<=20 && overlap>=.55*fmin(a.w,b.w);
    }
    return gap>=-2 && gap<=4.5 && fabs(a.x-b.x)<=3 && fabs((a.x+a.w)-(b.x+b.w))<=3;
}
/* Long messages can be many screens high. Both temporary corners stay well
   outside the viewport. Reuse the current window while its margins still hold. */
typedef struct {double min,max;} WXGBubbleSpan;
static inline WXGBubbleSpan WXGBubbleLocalSlice(double top,double bottom,double radius,int above,int below) {
    return (WXGBubbleSpan){top-(above?radius:0),bottom+(below?radius:0)};
}
// Flat chat tables do not expose a section per message. A verified missing
// end may extend offscreen only if its visible physical slice reaches that
// edge; otherwise the missing row could leave a visible gap.
static inline int WXGBubbleExtendIndexedSpan(WXGBubbleSpan *span,WXGBubbleSpan viewport,int missingHead,int missingTail) {
    if((missingHead && span->min>viewport.min+1) || (missingTail && span->max<viewport.max-1))return 0;
    double guard=2*fmax(120,(viewport.max-viewport.min)*.25);
    if(missingHead)span->min=fmin(span->min,viewport.min-guard);
    if(missingTail)span->max=fmax(span->max,viewport.max+guard);
    return 1;
}
static inline WXGBubbleSpan WXGBubbleRenderSpan(WXGBubbleSpan family,WXGBubbleSpan viewport,WXGBubbleSpan old) {
    double guard=fmax(120,(viewport.max-viewport.min)*.25);
    WXGBubbleSpan needed={fmax(family.min,viewport.min-guard),fmin(family.max,viewport.max+guard)};
    if(old.min>=family.min && old.max<=family.max && old.min<=needed.min && old.max>=needed.max &&
       old.max-old.min<=(viewport.max-viewport.min)+5*guard)return old;
    return (WXGBubbleSpan){fmax(family.min,viewport.min-2*guard),fmin(family.max,viewport.max+2*guard)};
}
#endif
