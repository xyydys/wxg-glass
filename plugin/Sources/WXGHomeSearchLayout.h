#ifndef WXG_HOME_SEARCH_LAYOUT_H
#define WXG_HOME_SEARCH_LAYOUT_H
#include "WXGGeometry.h"
#include <stdbool.h>

static inline bool WXGHomeSearchFieldReady(WXGRect field,double headerWidth,double headerHeight) {
    return isfinite(headerWidth) && isfinite(headerHeight) &&
        field.w>0 && field.h>0 && field.x>=-.5 && field.y>=-.5 &&
        field.x+field.w<=headerWidth+.5 && field.y+field.h<=headerHeight+.5;
}

static inline double WXGHomeSearchRequiredHeaderHeight(WXGRect field,double nativeHeight,double customHeight,double topGap) {
    if(customHeight<=.5 && topGap<0)return nativeHeight;
    double height=customHeight>.5?WXGBound(customHeight,24.,64.):field.h;
    double y=topGap>=0?topGap:field.y;
    double bottomPadding=fmax(4.,nativeHeight-field.y-field.h);
    return fmax(nativeHeight,y+height+bottomPadding);
}

typedef struct { double groupY, headerHeight, bottomGap; } WXGHomeGroupLayout;
static inline WXGHomeGroupLayout WXGHomeGroupBelowSearch(double nativeHeight,double nativeFieldBottom,
                                                          double searchBottom,double groupHeight,double gap) {
    double bottomGap=fmax(0,nativeHeight-nativeFieldBottom);
    double groupY=searchBottom+fmax(0,gap);
    return (WXGHomeGroupLayout){groupY,groupY+groupHeight+bottomGap,bottomGap};
}

static inline double WXGHomePixel(double value,double scale) {
    return scale>0 ? round(value*scale)/scale : value;
}

// During overscroll UIKit can move the title and the list header independently.
// Keep the measured screen gap until WeChat starts revealing its pull-down panel,
// then hand position back to that panel's native header continuously.
static inline double WXGHomePulledSearchY(double naturalY,double titleY,double gap,double panel) {
    double attached=titleY+gap;
    return attached+(naturalY-attached)*WXGBound(panel,0.,1.);
}

// The header's natural position follows contentOffset. The pin line only
// depends on the viewport, its adjusted inset, and the visible navigation row.
static inline double WXGFloatSearchPlacement(double naturalY,double gap,double viewportY,double inset,
                                             bool expectsNav,double navBottom,double safeTop,bool *atNative) {
    *atNative=false;
    if(!isfinite(naturalY) || !isfinite(gap) || !isfinite(viewportY) || !isfinite(inset) || gap<-.5)return NAN;
    double top=viewportY+inset;
    if(expectsNav) {
        if(!isfinite(navBottom) || !isfinite(safeTop) || navBottom<=safeTop+.5)return NAN;
        top=fmax(top,navBottom);
    }
    double pin=top+gap;
    *atNative=naturalY>=pin-.5;
    return fmax(naturalY,pin);
}
#endif
