#ifndef WXG_DROP_SHADOW_H
#define WXG_DROP_SHADOW_H
#include <math.h>
#include <stddef.h>
#include <stdint.h>
/* FIX114 K (user: the shadow iOS 26 puts around its glass): the glass's drop
   shadow as one image layer.

   Measured on the user's iOS 26 screenshot (a 44 pt back button over a light
   grey page and a white card): the page is darkened multiplicatively (the
   same ratio on grey and on white, so a black shadow), by 0.20 x the button's
   shape blurred with a Gaussian of sigma 17 pt and moved 8 pt down (about 6%
   darker beside the button, 9% below, 4% above, gone ~30 pt out; rms 0.25%).
   Apple: shadows grow more prominent over text and with the component's
   size (not modelled; every range sets its own).

   The image: the shape grown by `spread`, moved `offset` down, blurred with
   sigma `blur` (all points), times (1 - the shape itself), so nothing lies
   under the glass (its backdrop would capture it and the glass would turn
   grey). Black, the strength is the layer's opacity. Long shapes are drawn
   with a straight stretch of 2 x (3 sigma + spread + 2) pt only: past 3
   sigma from the ends the picture no longer changes along the side, so the
   middle column is stretched (contentsCenter) to any length. */
typedef struct {
    float shapeW,shapeH;   /* the shape as drawn in the image (pt) */
    float margin;          /* image edge to shape edge, each side (pt) */
    int stretchX,stretchY; /* the real shape is longer: stretch the middle */
} WXGShadowPlan;
static inline float WXGShadowClampf(float x,float a,float b) {return x<a?a:(x>b?b:x);}
static inline WXGShadowPlan WXGShadowPlanFor(float w,float h,float radius,float blur,float offset,float spread) {
    WXGShadowPlan p;
    float r=WXGShadowClampf(radius,0.f,fminf(w,h)*.5f),reach=3.f*fmaxf(blur,0.f)+fmaxf(spread,0.f)+2.f;
    float longest=2.f*r+2.f*reach;
    p.stretchX=w>longest+1.f;p.stretchY=h>longest+1.f;
    p.shapeW=p.stretchX?longest:w;p.shapeH=p.stretchY?longest:h;
    p.margin=ceilf(3.f*fmaxf(blur,0.f)+fmaxf(spread,0.f)+fabsf(offset))+1.f;
    return p;
}
/* Signed distance to a rounded rectangle centred at the origin (circular corners). */
static inline float WXGShadowRoundedSDF(float x,float y,float hx,float hy,float r) {
    float qx=fabsf(x)-(hx-r),qy=fabsf(y)-(hy-r);
    float ox=fmaxf(qx,0.f),oy=fmaxf(qy,0.f);
    return sqrtf(ox*ox+oy*oy)+fminf(fmaxf(qx,qy),0.f)-r;
}
static inline void WXGShadowBlurLine(const float *in,float *out,int n,int stride,const float *k,int kr) {
    for(int i=0;i<n;i++) {
        float s=0.f;
        for(int j=-kr;j<=kr;j++){int t=i+j;if(t<0 || t>=n)continue;s+=in[t*stride]*k[j+kr];}
        out[i*stride]=s;
    }
}
/* Fills `alpha` (pw x ph, row-major, 0..1) for the plan at `scale` px per pt.
   `scratch` holds 2 x pw x ph + 2 x pw + 2 x ph + 1024 floats. */
static inline void WXGShadowRender(float *alpha,int pw,int ph,float scale,WXGShadowPlan p,float radius,float blur,float offset,float spread,float *scratch) {
    float *grown=scratch,*tmp=grown+pw*ph,*line=tmp+pw*ph,*lineOut=line+(pw>ph?pw:ph),*kernel=lineOut+(pw>ph?pw:ph);
    float hx=p.shapeW*.5f,hy=p.shapeH*.5f,r=WXGShadowClampf(radius,0.f,fminf(hx,hy));
    float ghx=fmaxf(hx+spread,.01f),ghy=fmaxf(hy+spread,.01f),gr=WXGShadowClampf(r+spread,0.f,fminf(ghx,ghy));
    float ox=p.margin+hx,oy=p.margin+hy;   /* the shape's centre in the image (pt) */
    for(int j=0;j<ph;j++)for(int i=0;i<pw;i++) {
        float x=(i+.5f)/scale-ox,y=(j+.5f)/scale-oy;
        grown[j*pw+i]=WXGShadowClampf(.5f-WXGShadowRoundedSDF(x,y-offset,ghx,ghy,gr)*scale,0.f,1.f);
    }
    float sigma=fmaxf(blur,0.f)*scale;
    int kr=(int)ceilf(3.f*sigma);if(kr>500)kr=500;
    if(kr>=1) {
        float sum=0.f;
        for(int j=-kr;j<=kr;j++){kernel[j+kr]=expf(-.5f*(float)(j*j)/(sigma*sigma));sum+=kernel[j+kr];}
        for(int j=0;j<=2*kr;j++)kernel[j]/=sum;
        for(int j=0;j<ph;j++){for(int i=0;i<pw;i++)line[i]=grown[j*pw+i];WXGShadowBlurLine(line,lineOut,pw,1,kernel,kr);for(int i=0;i<pw;i++)tmp[j*pw+i]=lineOut[i];}
        for(int i=0;i<pw;i++){for(int j=0;j<ph;j++)line[j]=tmp[j*pw+i];WXGShadowBlurLine(line,lineOut,ph,1,kernel,kr);for(int j=0;j<ph;j++)grown[j*pw+i]=lineOut[j];}
    }
    /* Cut the shape out (0.5 pt inside its outline: the glass covers the
       rest, and Core Animation's continuous corners lie inside circular ones). */
    for(int j=0;j<ph;j++)for(int i=0;i<pw;i++) {
        float x=(i+.5f)/scale-ox,y=(j+.5f)/scale-oy;
        float hole=WXGShadowClampf(.5f-(WXGShadowRoundedSDF(x,y,hx,hy,r)+.5f)*scale,0.f,1.f);
        alpha[j*pw+i]=WXGShadowClampf(grown[j*pw+i],0.f,1.f)*(1.f-hole);
    }
}
static inline size_t WXGShadowScratchFloats(int pw,int ph) {return (size_t)pw*(size_t)ph*2+(size_t)(pw>ph?pw:ph)*2+1024;}
/* The image's size in pixels for a plan. */
static inline void WXGShadowPixels(WXGShadowPlan p,float scale,int *pw,int *ph) {
    *pw=(int)ceilf((p.shapeW+2.f*p.margin)*scale);*ph=(int)ceilf((p.shapeH+2.f*p.margin)*scale);
}
#endif
