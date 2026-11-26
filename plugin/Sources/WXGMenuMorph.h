#ifndef WXG_MENU_MORPH_H
#define WXG_MENU_MORPH_H

#include "WXGMenuCascade.h"
#include <stdbool.h>

/*
 * GlassMotion.kt, GlassMorphFrame.kt, GlassMorphTuning.kt and GlassSpring.kt
 * adapted to C from xyydys/expo-glass-custom-menu at 0021efd8ab0d.
 *
 * The MIT License (MIT)
 *
 * Copyright (c) 2015-present 650 Industries, Inc. (aka Expo)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/* The menu is drawn and hit-tested in a window overlay; the native popup's
 * clipped image wrapper can be much narrower and start below this viewport. */
static inline WXGMenuBox WXGMenuMorphPlacePanel(WXGMenuBox anchor,WXGMenuBox screen,WXGMenuBox viewport,double width,double height) {
    if(!(anchor.w>0. && anchor.h>0. && width>0. && height>0. &&
         width<=viewport.w && height<=viewport.h))return (WXGMenuBox){0};
    // The navigation button may already straddle the top or right safe-area inset.
    double right=fmin(screen.x+screen.w,fmax(viewport.x+viewport.w,anchor.x+anchor.w));
    double top=fmax(screen.y,fmin(viewport.y,anchor.y));
    double x=WXGMenuClamp(anchor.x+anchor.w-width,viewport.x,right-width);
    double below=viewport.y+viewport.h-anchor.y,above=anchor.y+anchor.h-top;
    double y=height>below && above>below?anchor.y+anchor.h-height:anchor.y;
    return (WXGMenuBox){x,WXGMenuClamp(y,top,viewport.y+viewport.h-height),width,height};
}

typedef enum {
    WXGMenuMorphPassThrough, WXGMenuMorphNativeBackdrop, WXGMenuMorphInsidePanel
} WXGMenuMorphHitZone;

static inline bool WXGMenuMorphPointInBox(WXGMenuBox box,double x,double y) {
    return x>=box.x && y>=box.y && x<box.x+box.w && y<box.y+box.h;
}

static inline WXGMenuMorphHitZone WXGMenuMorphHitZoneAt(WXGMenuBox panel,double x,double y,bool inNativePopup) {
    if(WXGMenuMorphPointInBox(panel,x,y))return WXGMenuMorphInsidePanel;
    return inNativePopup?WXGMenuMorphNativeBackdrop:WXGMenuMorphPassThrough;
}

typedef struct {
    WXGMenuBox bounds,sourceLobe;
    double radiusX,radiusY,sourceRadius,smoothing;
    double sourceOpacity,sourceZoom,sourceBlur;
    double rowsOpacity,contentProgress,contentBlur,contentZoom;
    double portalBlur,lensHeight,lensAmount;
} WXGMenuMorphFrame;

typedef struct { double damping,response; } WXGMenuMorphSpec;
typedef struct {
    double value,velocity,target;
    double omega,alpha,frequency;
    double valueTolerance,velocityTolerance;
} WXGMenuMorphSpring;

typedef enum {
    WXGMenuMorphX,WXGMenuMorphY,WXGMenuMorphWidth,WXGMenuMorphHeight,
    WXGMenuMorphRadiusX,WXGMenuMorphRadiusY,
    WXGMenuMorphSourceX,WXGMenuMorphSourceY,WXGMenuMorphSourceWidth,WXGMenuMorphSourceHeight,
    WXGMenuMorphSourceScale,WXGMenuMorphIncomingScale,WXGMenuMorphKick,WXGMenuMorphSourceKick,
    WXGMenuMorphContentChannel,WXGMenuMorphRows,WXGMenuMorphSourceContent,WXGMenuMorphLens,
    WXGMenuMorphPortalBlur,WXGMenuMorphSmoothing,WXGMenuMorphChannelCount
} WXGMenuMorphChannel;

typedef struct {
    WXGMenuMorphFrame frame;
    WXGMenuBox source,through,destination;
    double destinationRadius,zoomReferenceHeight,elapsed,absorbDuration;
    bool initialized,expanded,followsPress;
    bool correctionApplied,smoothingReleased,lensReleased;
    bool closingKickReleased,sourceKickReleased,portalBlurReleased;
    WXGMenuMorphSpring channels[WXGMenuMorphChannelCount];
} WXGMenuMorph;

static const WXGMenuMorphSpec WXGMenuMorphCollapseSpring={1.,.21};
static const WXGMenuMorphSpec WXGMenuMorphEjectSpring={.75,.32};
static const WXGMenuMorphSpec WXGMenuMorphKickSpring={1.,.14};
static const WXGMenuMorphSpec WXGMenuMorphBlurOutSpring={.8,.315};
static const WXGMenuMorphSpec WXGMenuMorphLensOffOpeningSpring={1.,.42};
static const WXGMenuMorphSpec WXGMenuMorphLensOffClosingSpring={1.,.28};
static const WXGMenuMorphSpec WXGMenuMorphAbsorbContentSpring={1.,.15};
static const WXGMenuMorphSpec WXGMenuMorphRowsRevealSpring={1.,.3};
static const WXGMenuMorphSpec WXGMenuMorphAbsorbSmoothingSpring={1.,.07};
static const WXGMenuMorphSpec WXGMenuMorphReleaseSmoothingSpring={1.,.42};

static inline bool WXGMenuMorphSpringSettled(const WXGMenuMorphSpring *spring) {
    return fabs(spring->value-spring->target)<spring->valueTolerance &&
           fabs(spring->velocity)<spring->velocityTolerance;
}

static inline void WXGMenuMorphSpringFinish(WXGMenuMorphSpring *spring) {
    spring->value=spring->target;
    spring->velocity=0.;
}

static inline void WXGMenuMorphSpringTarget(WXGMenuMorphSpring *spring,double target,WXGMenuMorphSpec spec) {
    spring->target=target;
    spring->omega=6.28318530717958647692/spec.response;
    spring->alpha=spec.damping*spring->omega;
    spring->frequency=spec.damping>=.9999?0.:spring->omega*sqrt(1.-spec.damping*spec.damping);
}

/* The analytic solution retains the velocity when its destination changes. */
static inline void WXGMenuMorphSpringAdvance(WXGMenuMorphSpring *spring,double seconds) {
    double displacement=spring->value-spring->target;
    double velocity=spring->velocity;
    if(displacement==0. && velocity==0.)return;
    double decay=exp(-spring->alpha*seconds);
    if(spring->frequency==0.) {
        double coefficient=velocity+spring->omega*displacement;
        spring->value=spring->target+decay*(displacement+coefficient*seconds);
        spring->velocity=decay*(velocity-spring->omega*coefficient*seconds);
    }else {
        double angle=spring->frequency*seconds;
        double cosine=cos(angle),sine=sin(angle);
        double coefficient=(velocity+spring->alpha*displacement)/spring->frequency;
        double wave=displacement*cosine+coefficient*sine;
        spring->value=spring->target+decay*wave;
        spring->velocity=decay*(-spring->alpha*wave+spring->frequency*(-displacement*sine+coefficient*cosine));
    }
    if(WXGMenuMorphSpringSettled(spring))WXGMenuMorphSpringFinish(spring);
}

static inline double WXGMenuMorphCenterX(WXGMenuBox box) { return box.x+box.w*.5; }
static inline double WXGMenuMorphCenterY(WXGMenuBox box) { return box.y+box.h*.5; }

static inline WXGMenuBox WXGMenuMorphCenteredBox(double x,double y,double w,double h) {
    return (WXGMenuBox){x-w*.5,y-h*.5,w,h};
}

/* The Android calculations use screen pixels and density. Using UIKit points
   directly retains its alignment to whole density-independent units. */
static inline double WXGMenuMorphAlignedCenter(double center,double start,double size,double inset,double diameter) {
    double minimum=start+inset,maximum=start+size-inset;
    double bounded=minimum<=maximum?WXGMenuClamp(center,minimum,maximum):start+size*.5;
    return round(bounded-diameter*.5)+diameter*.5;
}

static inline double WXGMenuMorphPressX(const WXGMenuMorph *motion) {
    return WXGMenuMorphAlignedCenter(WXGMenuMorphCenterX(motion->through),motion->source.x,
        motion->source.w,motion->through.w*.5,motion->destination.w);
}

static inline double WXGMenuMorphPressY(const WXGMenuMorph *motion) {
    return WXGMenuMorphAlignedCenter(WXGMenuMorphCenterY(motion->through),motion->source.y,
        motion->source.h,motion->through.h*.5,motion->destination.w);
}

static inline double WXGMenuMorphIncomingDiameter(const WXGMenuMorph *motion) {
    WXGMenuBox menu=motion->destination;
    return fmax(menu.w*.5*motion->through.h/fmax(menu.w,menu.h),1.);
}

static inline double WXGMenuMorphKickAmount(const WXGMenuMorph *motion,double points) {
    WXGMenuBox menu=motion->destination;
    double heightFactor=WXGMenuClamp((menu.h-60.)/140.,.5,1.);
    double anchorY=WXGMenuClamp((WXGMenuMorphCenterY(motion->through)-menu.y)/menu.h,0.,1.);
    return points*heightFactor*(2.*anchorY-1.);
}

static inline double WXGMenuMorphValue(const WXGMenuMorph *motion,WXGMenuMorphChannel channel) {
    return motion->channels[channel].value;
}

static inline void WXGMenuMorphTarget(WXGMenuMorph *motion,WXGMenuMorphChannel channel,double target,WXGMenuMorphSpec spec) {
    WXGMenuMorphSpringTarget(&motion->channels[channel],target,spec);
}

static inline void WXGMenuMorphPublish(WXGMenuMorph *motion) {
    WXGMenuMorphFrame *frame=&motion->frame;
    double incomingScale=fmax(WXGMenuMorphValue(motion,WXGMenuMorphIncomingScale),.001);
    double width=fmax(WXGMenuMorphValue(motion,WXGMenuMorphWidth)*incomingScale,1.);
    double height=fmax(WXGMenuMorphValue(motion,WXGMenuMorphHeight)*incomingScale,1.);
    double restingScale=WXGMenuMorphIncomingDiameter(motion)/fmax(motion->destination.w,1.);
    double growth=motion->followsPress?WXGMenuClamp((incomingScale-restingScale)/fmax(1.-restingScale,.001),0.,1.2):1.;
    double originX=WXGMenuMorphPressX(motion),originY=WXGMenuMorphPressY(motion);
    double x=originX+(WXGMenuMorphValue(motion,WXGMenuMorphX)-originX)*growth;
    double y=originY+(WXGMenuMorphValue(motion,WXGMenuMorphY)+WXGMenuMorphValue(motion,WXGMenuMorphKick)*incomingScale-originY)*growth;
    frame->bounds=WXGMenuMorphCenteredBox(x,y,width,height);

    double sourceScale=fmax(WXGMenuMorphValue(motion,WXGMenuMorphSourceScale),.01);
    double sourceWidth=fmax(WXGMenuMorphValue(motion,WXGMenuMorphSourceWidth)*sourceScale,1.);
    double sourceHeight=fmax(WXGMenuMorphValue(motion,WXGMenuMorphSourceHeight)*sourceScale,1.);
    double sourceY=WXGMenuMorphValue(motion,WXGMenuMorphSourceY)+WXGMenuMorphValue(motion,WXGMenuMorphSourceKick)*sourceScale;
    frame->sourceLobe=WXGMenuMorphCenteredBox(WXGMenuMorphValue(motion,WXGMenuMorphSourceX),sourceY,sourceWidth,sourceHeight);
    frame->sourceRadius=fmin(sourceWidth,sourceHeight)*.5;

    double lens=WXGMenuClamp(WXGMenuMorphValue(motion,WXGMenuMorphLens),0.,1.);
    double heightFactor=WXGMenuClamp((motion->zoomReferenceHeight-215.)/305.,0.,1.);
    double portal=WXGMenuMorphValue(motion,WXGMenuMorphPortalBlur);
    double zoom=1.+(.65-.45*heightFactor)*portal;
    frame->radiusX=fmax(WXGMenuMorphValue(motion,WXGMenuMorphRadiusX)*incomingScale,0.);
    frame->radiusY=fmax(WXGMenuMorphValue(motion,WXGMenuMorphRadiusY)*incomingScale,0.);
    frame->contentProgress=WXGMenuClamp(WXGMenuMorphValue(motion,WXGMenuMorphContentChannel),0.,1.);
    frame->smoothing=fmax(WXGMenuMorphValue(motion,WXGMenuMorphSmoothing),0.);
    frame->sourceOpacity=WXGMenuClamp(WXGMenuMorphValue(motion,WXGMenuMorphSourceContent),0.,1.);
    frame->sourceBlur=4.*(1.-frame->sourceOpacity);
    frame->sourceZoom=zoom;
    frame->rowsOpacity=WXGMenuClamp(WXGMenuMorphValue(motion,WXGMenuMorphRows),0.,1.);
    frame->contentBlur=18.*(1.-frame->rowsOpacity);
    frame->contentZoom=zoom;
    frame->portalBlur=6.*fmax(portal,0.);
    frame->lensHeight=75.*lens*fmin(fmin(width,height)/250.,1.);
    frame->lensAmount=fmin(-frame->lensHeight,-.001);
}

static inline void WXGMenuMorphConfigureExpansion(WXGMenuMorph *motion) {
    const WXGMenuBox source=motion->source,through=motion->through,menu=motion->destination;
    const double side=fmin(source.w,source.h),inset=side/8.;
    const double x=WXGMenuMorphAlignedCenter(WXGMenuMorphCenterX(through)*.75+WXGMenuMorphCenterX(menu)*.25,
        menu.x,menu.w,inset,side);
    const double y=WXGMenuMorphAlignedCenter(WXGMenuMorphCenterY(through)*.75+WXGMenuMorphCenterY(menu)*.25,
        menu.y,menu.h,inset,side);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceX,x,WXGMenuMorphEjectSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceY,y,WXGMenuMorphEjectSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceWidth,side,WXGMenuMorphCollapseSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceHeight,side,WXGMenuMorphCollapseSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceScale,.25,WXGMenuMorphEjectSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphX,WXGMenuMorphCenterX(menu),WXGMenuMorphEjectSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphY,WXGMenuMorphCenterY(menu),WXGMenuMorphEjectSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphWidth,menu.w,WXGMenuMorphEjectSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphHeight,menu.h,WXGMenuMorphEjectSpring);
    double radius=motion->correctionApplied?motion->destinationRadius:menu.w;
    WXGMenuMorphTarget(motion,WXGMenuMorphRadiusX,radius,WXGMenuMorphEjectSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphRadiusY,radius,WXGMenuMorphEjectSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphKick,motion->correctionApplied?0.:WXGMenuMorphKickAmount(motion,-80.),WXGMenuMorphKickSpring);
}

static inline void WXGMenuMorphConfigureCollapse(WXGMenuMorph *motion) {
    const WXGMenuBox source=motion->source,menu=motion->destination;
    const WXGMenuMorphSpec absorb={.8,motion->absorbDuration};
    double x=motion->followsPress?WXGMenuMorphPressX(motion):WXGMenuMorphCenterX(source);
    double y=motion->followsPress?WXGMenuMorphPressY(motion):WXGMenuMorphCenterY(source);
    WXGMenuMorphTarget(motion,WXGMenuMorphX,x,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphY,y,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphWidth,menu.w*.84,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphHeight,menu.w,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphIncomingScale,WXGMenuMorphIncomingDiameter(motion)/menu.w,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphRadiusX,menu.w*.5,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphRadiusY,menu.w*.5,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceX,WXGMenuMorphCenterX(source),absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceY,WXGMenuMorphCenterY(source),absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceWidth,source.w,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceHeight,source.h,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceScale,1.,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphKick,motion->closingKickReleased?0.:WXGMenuMorphKickAmount(motion,-80.),WXGMenuMorphKickSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceKick,motion->sourceKickReleased?0.:WXGMenuMorphKickAmount(motion,40.),WXGMenuMorphKickSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphContentChannel,0.,WXGMenuMorphAbsorbContentSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphRows,0.,WXGMenuMorphAbsorbContentSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphSourceContent,1.,absorb);
    WXGMenuMorphTarget(motion,WXGMenuMorphSmoothing,motion->smoothingReleased?0.:20.,
        motion->smoothingReleased?WXGMenuMorphReleaseSmoothingSpring:WXGMenuMorphAbsorbSmoothingSpring);
}

static inline void WXGMenuMorphInitialize(WXGMenuMorph *motion,WXGMenuBox source,WXGMenuBox target,double targetRadius,WXGMenuBox through,bool fromPress) {
    *motion=(WXGMenuMorph){0};
    if(!(source.w>0. && source.h>0. && target.w>0. && target.h>0. && through.w>0. && through.h>0.))return;
    motion->source=source;
    motion->through=through;
    motion->destination=target;
    motion->destinationRadius=fmin(targetRadius,fmin(target.w,target.h)*.5);
    motion->zoomReferenceHeight=target.h;
    motion->followsPress=fromPress;
    motion->absorbDuration=.35;
    const double initial[WXGMenuMorphChannelCount]={
        [WXGMenuMorphX]=WXGMenuMorphPressX(motion),
        [WXGMenuMorphY]=WXGMenuMorphPressY(motion),
        [WXGMenuMorphWidth]=target.w,
        [WXGMenuMorphHeight]=target.w,
        [WXGMenuMorphRadiusX]=target.w*.5,
        [WXGMenuMorphRadiusY]=target.w*.5,
        [WXGMenuMorphSourceX]=WXGMenuMorphCenterX(source),
        [WXGMenuMorphSourceY]=WXGMenuMorphCenterY(source),
        [WXGMenuMorphSourceWidth]=source.w,
        [WXGMenuMorphSourceHeight]=source.h,
        [WXGMenuMorphSourceScale]=1.,
        [WXGMenuMorphIncomingScale]=WXGMenuMorphIncomingDiameter(motion)/target.w,
        [WXGMenuMorphSourceContent]=1.,
        [WXGMenuMorphLens]=1.,
    };
    for(int i=0;i<WXGMenuMorphChannelCount;++i) {
        WXGMenuMorphSpring *spring=&motion->channels[i];
        WXGMenuMorphSpringTarget(spring,initial[i],WXGMenuMorphRowsRevealSpring);
        WXGMenuMorphSpringFinish(spring);
        spring->valueTolerance=.2;
        spring->velocityTolerance=3.;
        if(i==WXGMenuMorphSourceScale || i==WXGMenuMorphIncomingScale) {
            spring->valueTolerance=.0005;
            spring->velocityTolerance=.01;
        }else if(i>=WXGMenuMorphContentChannel && i<=WXGMenuMorphPortalBlur) {
            spring->valueTolerance=.001;
            spring->velocityTolerance=.01;
        }else if(i==WXGMenuMorphSmoothing) {
            spring->valueTolerance=.05;
            spring->velocityTolerance=1.;
        }
    }
    motion->initialized=true;
    WXGMenuMorphPublish(motion);
}

static inline void WXGMenuMorphSetAbsorbDuration(WXGMenuMorph *motion,double seconds) {
    if(isfinite(seconds))motion->absorbDuration=fmax(seconds,.02);
}

static inline void WXGMenuMorphUpdateSource(WXGMenuMorph *motion,WXGMenuBox source,WXGMenuBox through) {
    if(!motion->initialized || !(source.w>0. && source.h>0. && through.w>0. && through.h>0.))return;
    motion->source=source;
    motion->through=through;
    if(!motion->expanded)WXGMenuMorphConfigureCollapse(motion);
}

static inline void WXGMenuMorphUpdateTarget(WXGMenuMorph *motion,WXGMenuBox target,double radius) {
    if(!motion->initialized || !(target.w>0. && target.h>0.))return;
    motion->destination=target;
    motion->destinationRadius=fmin(radius,fmin(target.w,target.h)*.5);
    if(motion->expanded)WXGMenuMorphConfigureExpansion(motion);
    else WXGMenuMorphConfigureCollapse(motion);
    WXGMenuMorphPublish(motion);
}

static inline void WXGMenuMorphSetExpanded(WXGMenuMorph *motion,bool expanded) {
    if(!motion->initialized)return;
    motion->expanded=expanded;
    motion->zoomReferenceHeight=motion->destination.h;
    motion->elapsed=0.;
    motion->correctionApplied=false;
    motion->smoothingReleased=false;
    motion->lensReleased=false;
    motion->closingKickReleased=false;
    motion->sourceKickReleased=expanded;
    motion->portalBlurReleased=false;
    WXGMenuMorphTarget(motion,WXGMenuMorphPortalBlur,1.,WXGMenuMorphCollapseSpring);
    WXGMenuMorphTarget(motion,WXGMenuMorphLens,1.,WXGMenuMorphKickSpring);
    if(expanded) {
        WXGMenuMorphConfigureExpansion(motion);
        WXGMenuMorphTarget(motion,WXGMenuMorphIncomingScale,1.,WXGMenuMorphEjectSpring);
        WXGMenuMorphTarget(motion,WXGMenuMorphSourceKick,0.,WXGMenuMorphKickSpring);
        WXGMenuMorphTarget(motion,WXGMenuMorphSourceContent,0.,WXGMenuMorphEjectSpring);
        WXGMenuMorphTarget(motion,WXGMenuMorphContentChannel,1.,WXGMenuMorphEjectSpring);
        WXGMenuMorphTarget(motion,WXGMenuMorphRows,1.,WXGMenuMorphRowsRevealSpring);
        WXGMenuMorphTarget(motion,WXGMenuMorphSmoothing,20.,WXGMenuMorphCollapseSpring);
    }else {
        WXGMenuMorphConfigureCollapse(motion);
    }
    WXGMenuMorphPublish(motion);
}

/* Preserve the sub-frame event timings when a display tick crosses a stage. */
static inline double WXGMenuMorphTimeline(WXGMenuMorph *motion) {
    double next=INFINITY,now=motion->elapsed+1e-6;
    double opticsDelay=motion->expanded?.084:.07;
    if(!motion->lensReleased || !motion->portalBlurReleased) {
        if(now>=opticsDelay) {
            motion->lensReleased=motion->portalBlurReleased=true;
            WXGMenuMorphTarget(motion,WXGMenuMorphPortalBlur,0.,WXGMenuMorphBlurOutSpring);
            WXGMenuMorphTarget(motion,WXGMenuMorphLens,0.,
                motion->expanded?WXGMenuMorphLensOffOpeningSpring:WXGMenuMorphLensOffClosingSpring);
        }else next=opticsDelay;
    }
    if(motion->expanded && !motion->correctionApplied) {
        if(now>=.07) {
            motion->correctionApplied=true;
            WXGMenuMorphTarget(motion,WXGMenuMorphRadiusX,motion->destinationRadius,WXGMenuMorphEjectSpring);
            WXGMenuMorphTarget(motion,WXGMenuMorphRadiusY,motion->destinationRadius,WXGMenuMorphEjectSpring);
            WXGMenuMorphTarget(motion,WXGMenuMorphKick,0.,WXGMenuMorphKickSpring);
        }else next=fmin(next,.07);
    }
    if(!motion->expanded && !motion->closingKickReleased) {
        if(now>=.07) {
            motion->closingKickReleased=true;
            WXGMenuMorphTarget(motion,WXGMenuMorphKick,0.,WXGMenuMorphKickSpring);
        }else next=fmin(next,.07);
    }
    if(!motion->sourceKickReleased) {
        if(now>=.105) {
            motion->sourceKickReleased=true;
            WXGMenuMorphTarget(motion,WXGMenuMorphSourceKick,0.,WXGMenuMorphKickSpring);
        }else next=fmin(next,.105);
    }
    double smoothingDelay=motion->expanded?.21:.07;
    if(!motion->smoothingReleased) {
        if(now>=smoothingDelay) {
            motion->smoothingReleased=true;
            WXGMenuMorphTarget(motion,WXGMenuMorphSmoothing,0.,WXGMenuMorphReleaseSmoothingSpring);
        }else next=fmin(next,smoothingDelay);
    }
    return next;
}

static inline bool WXGMenuMorphVisuallyCollapsed(const WXGMenuMorph *motion) {
    const WXGMenuMorphFrame *frame=&motion->frame;
    const WXGMenuBox shell=frame->sourceLobe,incoming=frame->bounds,source=motion->source;
    const double epsilon=.5,sourceRight=source.x+source.w,sourceBottom=source.y+source.h;
    if(fabs(shell.x-source.x)>epsilon || fabs(shell.y-source.y)>epsilon ||
       fabs(shell.x+shell.w-sourceRight)>epsilon || fabs(shell.y+shell.h-sourceBottom)>epsilon)return false;
    return incoming.x>=source.x-epsilon && incoming.y>=source.y-epsilon &&
        incoming.x+incoming.w<=sourceRight+epsilon && incoming.y+incoming.h<=sourceBottom+epsilon &&
        frame->contentProgress<.02 && frame->sourceOpacity>.98 &&
        fabs(WXGMenuMorphValue(motion,WXGMenuMorphKick))<epsilon &&
        fabs(WXGMenuMorphValue(motion,WXGMenuMorphSourceKick))<epsilon &&
        frame->smoothing<epsilon && WXGMenuMorphValue(motion,WXGMenuMorphLens)<.02;
}

static inline bool WXGMenuMorphAdvance(WXGMenuMorph *motion,double seconds) {
    if(!motion->initialized)return true;
    double remaining=isfinite(seconds)?fmax(seconds,0.):0.;
    while(remaining>0.) {
        double next=WXGMenuMorphTimeline(motion);
        double step=fmin(remaining,next-motion->elapsed);
        for(int i=0;i<WXGMenuMorphChannelCount;++i)WXGMenuMorphSpringAdvance(&motion->channels[i],step);
        motion->elapsed+=step;
        remaining-=step;
    }
    WXGMenuMorphTimeline(motion);
    WXGMenuMorphPublish(motion);
    if(!motion->expanded && WXGMenuMorphVisuallyCollapsed(motion)) {
        for(int i=0;i<WXGMenuMorphChannelCount;++i)WXGMenuMorphSpringFinish(&motion->channels[i]);
        WXGMenuMorphPublish(motion);
        return true;
    }
    if(motion->expanded && !motion->smoothingReleased)return false;
    for(int i=0;i<WXGMenuMorphChannelCount;++i)if(!WXGMenuMorphSpringSettled(&motion->channels[i]))return false;
    return true;
}

#endif
