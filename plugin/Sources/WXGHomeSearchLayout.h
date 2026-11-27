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

// Both rows take their zero setting from the same unmodified native field.
static inline WXGRect WXGHomeRowRect(WXGRect native,double available,double percent,double height,double top) {
    WXGRect row=native;
    if(percent>.5) {
        double minimum=fmin(120.,available);
        row.w=WXGBound(available*percent/100.,minimum,fmax(minimum,available-4.));
        row.x=(available-row.w)*.5;
    }
    if(height>.5)row.h=WXGBound(height,24.,64.);
    if(top>=0)row.y=top;
    return row;
}

// Distance between the header at the scroll view's natural top and visible navigation.
static inline double WXGHomeHeaderLeading(double viewportTop,double inset,double headerY,double chromeBottom) {
    return fmax(0,chromeBottom-(viewportTop+inset+headerY));
}

static inline bool WXGHomeShouldReveal(double offset,double rest,double headerHeight,bool touched) {
    double skipped=offset-rest;
    // UIKit can still be at absolute zero when it first publishes a top inset.
    bool initialZero=fabs(offset)<=.5 && rest<0;
    return !touched && skipped>.5 && (skipped<=headerHeight+1 || initialZero);
}

typedef struct { double groupY, headerHeight, bottomGap; } WXGHomeGroupLayout;
static inline WXGHomeGroupLayout WXGHomeGroupBelowSearch(double nativeHeight,double nativeFieldBottom,
                                                          double searchBottom,double groupHeight,double gap) {
    double bottomGap=fmax(0,nativeHeight-nativeFieldBottom);
    double groupY=searchBottom+fmax(0,gap);
    return (WXGHomeGroupLayout){groupY,groupY+groupHeight+bottomGap,bottomGap};
}

// Preserve the reservation for another search instance or for the native
// search-sized spacer. Unrelated native headers keep their own size.
static inline bool WXGHomeKeepsReservation(bool hasHeader,bool same,bool hasSearch,bool emptySpacer,bool keepEmpty,
                                           double height,double nativeHeight) {
    if(!hasHeader)return keepEmpty;
    return same || hasSearch || (emptySpacer && nativeHeight>0 && fabs(height-nativeHeight)<=1.);
}

// A replacement occupies exactly one row and uses the same bottom margin.
static inline WXGHomeGroupLayout WXGHomeRows(bool coexist,WXGRect native,double nativeHeight,
                                             WXGRect search,double groupHeight,double gap) {
    if(coexist)return WXGHomeGroupBelowSearch(nativeHeight,native.y+native.h,search.y+search.h,groupHeight,gap);
    double bottom=fmax(0.,nativeHeight-native.y-native.h);
    return (WXGHomeGroupLayout){search.y,search.y+groupHeight+bottom,bottom};
}

// Keep the same point in the conversation list when its header changes height.
// Inside the header, keep the user's depth from the natural top.
static inline double WXGHomeDepthAfterResize(double depth,double oldHeight,double newHeight) {
    if(oldHeight<=0)return depth;
    if(depth>=oldHeight)return depth+newHeight-oldHeight;
    return fmin(depth,newHeight);
}

static inline double WXGHomeOffsetAtDepth(double depth,double oldHeight,double newHeight,
                                         double topInset,double bottomInset,double content,double viewport) {
    double wanted=WXGHomeDepthAfterResize(depth,oldHeight,newHeight)-topInset;
    return WXGBound(wanted,-topInset,fmax(-topInset,content+bottomInset-viewport));
}

static inline double WXGHomePixel(double value,double scale) {
    return scale>0 ? round(value*scale)/scale : value;
}

static inline bool WXGHomeSameInset(double a,double b,double scale) {
    return fabs(a-b)<=1./fmax(1.,scale)+.01;
}

// A full-screen taskbar or refresh inset can also exceed the navigation height.
// Only the independently observed native AND automatic copies identify the duplicate.
static inline bool WXGHomeHasTwoNavigationInsets(double rest,double raw,double adjusted,double scale) {
    return rest>=20. && WXGHomeSameInset(raw,rest,scale) && WXGHomeSameInset(adjusted-raw,rest,scale);
}

static inline double WXGHomeRestInset(double chrome,double raw,double adjusted,double scale) {
    if(!isfinite(chrome) || chrome<20.)return 0.;
    if(fabs(chrome-adjusted)<=2.)return adjusted;
    if(fabs(chrome-raw)<=2. && WXGHomeHasTwoNavigationInsets(raw,raw,adjusted,scale))return raw;
    return 0.;
}

static inline double WXGHomeEffectiveTop(double rest,double raw,double adjusted,double scale) {
    return WXGHomeHasTwoNavigationInsets(rest,raw,adjusted,scale)?raw:adjusted;
}

// Before the conversation row has calibrated, keep a legitimate app-supplied
// top (including zero). Only a duplicated chrome or a full-screen range gives
// independent evidence that the adjusted top is not the resting position.
static inline double WXGHomeInitialConversationTop(double raw,double adjusted,double viewport,double scale) {
    double automatic=adjusted-raw;
    if((viewport>0 && adjusted>=viewport-1./fmax(1.,scale)) || WXGHomeHasTwoNavigationInsets(automatic,raw,adjusted,scale))
        return fmax(0.,automatic);
    return adjusted;
}
// A native animated scroll does not set tracking, dragging or decelerating.
// Its enlarged range remains authoritative all the way through the close.
static inline bool WXGHomeNativePull(double rest,double raw,double adjusted,double offset,double viewport,double scale) {
    double pixel=1./fmax(1.,scale)+.01;
    if(rest<20.)return offset < -rest-pixel || (viewport>0. && adjusted>=viewport-pixel);
    return offset < -rest-pixel || WXGHomeEffectiveTop(rest,raw,adjusted,scale)>rest+pixel;
}

// The native setter requested zero but forwarded a full chrome height into
// UIKit, which adds its own automatic contribution. Other requests pass through.
static inline bool WXGHomeDuplicatesZeroRequest(double requested,double forwarded,double automatic,double rest,double scale) {
    return requested==0. && WXGHomeHasTwoNavigationInsets(rest,forwarded,forwarded+automatic,scale);
}
static inline bool WXGHomeAtDuplicatedRest(double rest,double raw,double adjusted,double offset,double scale) {
    return WXGHomeHasTwoNavigationInsets(rest,raw,adjusted,scale) && WXGHomeSameInset(-offset,adjusted,scale);
}

// The list has already rubber-banded contentOffset. Sample it once in this
// coordinate system; title, search and groups must use the same displacement.
static inline double WXGHomePullTranslation(double offset,double inset,double scale) {
    return WXGHomePixel(fmax(0.,-(offset+inset)),scale);
}
// On release the close-area copy can already be parked above the navigation
// row while its presentation opacity still wins. Its action remains usable.
static inline double WXGHomePlusPullCenter(double closeAreaCenter,double navCenter,double pull) {
    return closeAreaCenter<navCenter ? navCenter+pull : closeAreaCenter;
}
// WeChat crossfades two native rows. A zero-opacity search icon is normal on
// an otherwise visible row, so callers measure its container, not that icon.
static inline bool WXGHomeUsesPullControls(double navAlpha,double listAlpha,bool pulling) {
    if(listAlpha<0.)return false;
    if(navAlpha<0.)return true;
    if(listAlpha<=.01 && navAlpha>.01)return false;
    if(navAlpha<=.01 && listAlpha>.01)return true;
    if(fabs(listAlpha-navAlpha)>.02)return listAlpha>navAlpha;
    return pulling;
}
static inline bool WXGHomeWaitsForSearchArtwork(bool currentHasBox,bool nextHasBox,bool editing,bool hasPlaceholder) {
    return currentHasBox && !nextHasBox && !editing && !hasPlaceholder;
}
static inline double WXGHomeFloatingRowY(double viewportTop,double inset,double headerY,double rowY,
                                         double offset,double scale) {
    return WXGHomePixel(viewportTop+inset+headerY+rowY,scale)+WXGHomePullTranslation(offset,inset,scale);
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
