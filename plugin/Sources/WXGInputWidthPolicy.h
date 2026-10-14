#ifndef WXG_INPUT_WIDTH_POLICY_H
#define WXG_INPUT_WIDTH_POLICY_H
#include "WXGGeometry.h"
#include <math.h>

// Keep the horizontal editing area stable BEFORE MMGrowTextView lays out its
// native UITextView. Native y/height continue to own wrapping and keyboard motion.
static inline WXGRect WXGInputAcceptHorizontal(WXGRect native, WXGRect target) {
    native.x=target.x;native.w=target.w;return native;
}
static inline WXGRect WXGInputRememberHorizontal(WXGRect saved, WXGRect incoming, WXGRect target) {
    if(fabs(incoming.x-target.x)>.01)saved.x=incoming.x;
    if(fabs(incoming.w-target.w)>.01)saved.w=incoming.w;
    saved.y=incoming.y;saved.h=incoming.h;return saved;
}
static inline double WXGInputAcceptedCenterX(WXGRect target,double currentWidth) {
    return target.x+currentWidth*.5;
}
#endif
