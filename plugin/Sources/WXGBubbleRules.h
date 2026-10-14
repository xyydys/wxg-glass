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
#endif
