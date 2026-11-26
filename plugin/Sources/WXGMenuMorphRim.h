#ifndef WXG_MENU_MORPH_RIM_H
#define WXG_MENU_MORPH_RIM_H

#include <stdint.h>
#include "WXGRim26.h"
#include "WXGRimGlow.h"
#include "WXGMenuMorphField.h"

// Same material tone and edge matrix as the live Other-glass renderer, in
// display sRGB. The resulting colour is opaque until the edge profile is
// applied. A moving rim must supply actual colour even on the first frame.
static inline void WXGMenuMorphRimColour(const uint8_t scene[3], double saturation, double brightness,
                                         const double veil[4], const float matrix[20], uint8_t out[3]) {
    double luma=(.2126*scene[0]+.7152*scene[1]+.0722*scene[2])/255.;
    double face[3], edge[3];
    for(int i=0;i<3;i++) {
        double channel=WXGRim26Clamp(luma+saturation*(scene[i]/255.-luma)+brightness,0,1);
        face[i]=channel+(veil[i]-channel)*veil[3];
    }
    WXGRim26Colour(matrix,face,1.,edge);
    for(int i=0;i<3;i++) out[i]=(uint8_t)lround(255.*edge[i]);
}

static inline void WXGMenuMorphRimPixel(uint8_t out[4], const uint8_t colour[3], double alpha) {
    unsigned a=(unsigned)lround(255.*WXGRim26Clamp(alpha,0,1));
    for(int i=0;i<3;i++) out[i]=(uint8_t)((colour[i]*a+127u)/255u);
    out[3]=(uint8_t)a;
}
typedef struct {
    const uint8_t *rgb;
    size_t width,height;
    float x,y,du,dv;
} WXGMorphRimColours;

// Sample the low-resolution scene at its pixel centres. As the menu moves
// over text, neighbouring colours blend rather than snapping on a texel edge.
static inline void WXGMenuMorphRimSample(WXGMorphRimColours colours,float px,float py,uint8_t rgb[3]) {
    float u=WXGRim26Clamp((px-colours.x)*colours.du-.5,0,colours.width-1);
    float v=WXGRim26Clamp((py-colours.y)*colours.dv-.5,0,colours.height-1);
    size_t x=(size_t)u,y=(size_t)v;
    size_t x1=x+1<colours.width?x+1:x,y1=y+1<colours.height?y+1:y;
    const uint8_t *tl=colours.rgb+3*(y*colours.width+x),*tr=colours.rgb+3*(y*colours.width+x1);
    const uint8_t *bl=colours.rgb+3*(y1*colours.width+x),*br=colours.rgb+3*(y1*colours.width+x1);
    u-=x;v-=y;
    for(int k=0;k<3;k++) {
        float top=tl[k]+u*(tr[k]-tl[k]),bottom=bl[k]+u*(br[k]-bl[k]);
        rgb[k]=(uint8_t)lroundf(top+v*(bottom-top));
    }
}

enum { WXGMorphAngularSteps=256 };
typedef struct {
    bool glow;
    WXGRim26Shape shape;
    double opacity;
    WXGRimGlowShape lights[WXGRimGlowCount];
    float levels[1+WXGRimGlowCount][WXGMorphAngularSteps+1];
    float angleX[1+WXGRimGlowCount],angleY[1+WXGRimGlowCount];
} WXGMorphRimLights;

static inline void WXGMenuMorphRimPrepareLights(WXGMorphRimLights *p) {
    for(int k=p->glow?1:0;k<(p->glow?1+WXGRimGlowCount:1);k++) {
        double angle=k?p->lights[k-1].angle:p->shape.angle;
        p->angleX[k]=(float)sin(angle*M_PI/180.); p->angleY[k]=(float)cos(angle*M_PI/180.);
        WXGRim26Shape angular=p->shape; angular.angle=0;
        for(int i=0;i<=WXGMorphAngularSteps;i++) {
            double dot=2.*i/WXGMorphAngularSteps-1.;
            p->levels[k][i]=k?WXGRimGlowLevel(0,dot,0,p->lights[k-1].endLevel,p->lights[k-1].sharpness):WXGRim26Along(0,dot,angular);
        }
    }
}

static inline float WXGMorphAngularValue(const WXGMorphRimLights *p,int k,WXGMenuMorphFieldSample f) {
    float cosine=f.dx*p->angleX[k]+f.dy*p->angleY[k];
    float index=(fminf(1,fmaxf(-1,cosine))+1)*(WXGMorphAngularSteps*.5f);
    int i=(int)fminf(index,WXGMorphAngularSteps-1);
    return p->levels[k][i]+(index-i)*(p->levels[k][i+1]-p->levels[k][i]);
}

static inline float WXGMenuMorphRimReach(const WXGMorphRimLights *p) {
    if(!p->glow)return p->opacity>.002?p->shape.height:0;
    double reach=0;
    for(int k=0;k<WXGRimGlowCount;k++)if(p->lights[k].alpha>.001)reach=fmax(reach,p->lights[k].width);
    return (float)reach;
}

// The outer contour is clipped by Core Animation, so allow a small colour
// bleed outside the field. The destination is a zero-initialized sRGB RGBA
// image. Pixels far from the perimeter are skipped entirely.
static inline void WXGMenuMorphRimDraw(const WXGMenuMorphField *field,WXGMenuMorphFieldBox box,
                                       int w,int h,uint8_t *pixels,const WXGMorphRimLights *p,WXGMorphRimColours colours) {
    float reach=WXGMenuMorphRimReach(p);
    if(w<=0 || h<=0 || box.width<=0 || box.height<=0 || reach<=0)return;
    float xs=w/box.width,ys=h/box.height;
    for(int j=0;j+1<field->height;j++)for(int i=0;i+1<field->width;i++) {
        const float *cell=field->values+j*field->width+i;
        float a=cell[0],d=cell[field->width+1],r=cell[1],l=cell[field->width];
        float grad=hypotf(fmaxf(fabsf(a-r),fabsf(l-d)),fmaxf(fabsf(a-l),fabsf(r-d)))/field->step;
        if(fminf(fminf(a,r),fminf(l,d))>grad*1.5f || fmaxf(fmaxf(a,r),fmaxf(l,d)) < -grad*(reach+1.5f))continue;
        float x0=field->x+i*field->step-box.x,y0=field->y+j*field->step-box.y;
        int left=fmaxf(0,ceilf(x0*xs-.5f)),right=fminf(w,ceilf((x0+field->step)*xs-.5f));
        int top=fmaxf(0,ceilf(y0*ys-.5f)),bottom=fminf(h,ceilf((y0+field->step)*ys-.5f));
        for(int y=top;y<bottom;y++)for(int x=left;x<right;x++) {
            float px=box.x+(x+.5f)/xs,py=box.y+(y+.5f)/ys;
            WXGMenuMorphFieldSample f=WXGMenuMorphFieldRead(field,px,py);
            float depth=fmaxf(0,-f.distance);
            if(depth>reach || f.distance>1.5f)continue;
            uint8_t *out=pixels+4*((size_t)y*w+x);
            if(!p->glow) {
                double light=WXGMorphAngularValue(p,0,f)*WXGRim26Across(depth,p->shape);
                double opacity=(light+(1.-light)*WXGRim26Ring(depth,p->shape))*p->opacity;
                uint8_t colour[3]; WXGMenuMorphRimSample(colours,px,py,colour);
                WXGMenuMorphRimPixel(out,colour,opacity);
                continue;
            }
            double rgba[4]={0};
            for(int k=0;k<WXGRimGlowCount;k++) {
                WXGRimGlowShape g=p->lights[k];
                if(g.width<=depth || g.alpha<=.001)continue;
                double alpha=g.alpha*pow(1.-depth/g.width,fmax(.05,g.falloff))*WXGMorphAngularValue(p,k+1,f);
                rgba[0]=g.red*alpha+rgba[0]*(1.-alpha);
                rgba[1]=g.green*alpha+rgba[1]*(1.-alpha);
                rgba[2]=g.blue*alpha+rgba[2]*(1.-alpha);
                rgba[3]=alpha+rgba[3]*(1.-alpha);
            }
            for(int n=0;n<4;n++)out[n]=(uint8_t)lround(255.*WXGRim26Clamp(rgba[n],0,1));
        }
    }
}
#endif
