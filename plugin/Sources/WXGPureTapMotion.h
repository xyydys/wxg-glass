#ifndef WXG_PURE_TAP_MOTION_H
#define WXG_PURE_TAP_MOTION_H

#include "WXGDockScript.h"
#include "WXGDockSystem.h"
#include "WXGLensFlex.h"

/* Apply the same end-anchored elastic deformation to both the live finger
   lens and the render-server samples. The bar and tab pitch stay stationary. */
static inline WXGDockGeometry WXGFlexDockGeometry(WXGDockGeometry g,double sx,double sy,
                                                  double wrap,double press,double cellPosition) {
    float w=WXG_MIN((float)(g.lensWidth*sx),g.barWidth+2.f*(float)wrap);
    float h=(float)WXGLensFlexRestingHeight(g.lensHeight*sy,g.barHeight,press,1.);
    g.lensX+=(g.lensWidth-w)*(float)WXGScriptClamp(cellPosition,0,1);
    g.lensY+=(g.lensHeight-h)*.5f;
    g.lensWidth=w;g.lensHeight=h;
    return g;
}

typedef struct {
    float width,height,gap,extra,originX,growth,barGrowth,wrap,liftWidth;
    WXGLensFlexParams flex;
    int elastic;
} WXGPureTapLayout;

typedef struct {
    double press,selection;
    WXGDockGeometry geometry;
    WXGLensFlex flex;
} WXGPureTapPose;

static inline WXGPureTapPose WXGPureTapSample(const WXGDockScript *script,WXGPureTapLayout layout,
                                              WXGLensFlex prior,double time,double dt) {
    double velocity=0,x=WXGScriptMoveAt(script,time,&velocity)-layout.originX;
    double p=WXGScriptClamp(WXGScriptPressValue(script,time),0,1);
    WXGDockGeometry g=WXGDockLayoutCells(layout.width,layout.height,layout.gap,(float)x,(float)p,
        layout.growth,0,layout.barGrowth,layout.wrap,layout.extra,layout.liftWidth);
    float pitch=WXGDockCellPitch(layout.width,layout.gap,layout.extra);
    if(dt>0)WXGLensFlexAdaptiveStep(&prior,velocity,pitch,layout.flex,dt);
    if(layout.elastic) {
        double sx=1,sy=1;
        WXGLensFlexAdaptiveScaleAt(prior,layout.flex,p,&sx,&sy);
        float first=WXGDockCellCenter(layout.width,layout.gap,layout.extra,0);
        g=WXGFlexDockGeometry(g,sx,sy,layout.wrap,p,(x-first)/WXG_MAX(1.f,pitch*3));
    }
    WXGPureTapPose pose={p,WXGScriptSelectValue(script,time),g,prior};
    return pose;
}
#endif
