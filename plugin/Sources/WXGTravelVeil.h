#ifndef WXG_TRAVEL_VEIL_H
#define WXG_TRAVEL_VEIL_H
#include "WXGLensOptics.h"
/* FIX88: the dock's tap animation (render server, WXGDemoBar travel layers)
   draws the bar seen through its lens like the real lens does: inset by the
   lens (WXGInnerInsetAlong, 45 degrees at the join) and with the material's
   edge fade. Pure C, the same rules as the shader.

   The bar's outline (a capsule centred bx, by, bw x bh) sampled at n x
   positions from x0 to x1 along the top (left to right) and the bottom (right
   to left), each point moved inward along the outline's normal by the lens
   inset there plus `extra`: 2n points in the same space. Past the bar's end
   the samples stay on the end. The offset stops just short of the bar's
   middle (the deepest bands never cross). The lens is a capsule centred lx, ly, lw x lh.
   `insetHeight` is the shader's u.bar.w * u.motion.x. */
/* FIX94: the bar following the lens' rim (WXGLensBarZoom; NULL or margin 0:
   off): each point moved vertically about the bar's centre by the scale of
   its column, as the shader samples the bar. */
typedef struct {float side,ratio,sharpness,margin;} WXGLensFollow;
static inline void WXGTravelVeilOutline(float bx,float by,float bw,float bh,float lx,float ly,float lw,float lh,
                                        float insetHeight,float press,float pinch,float extra,float x0,float x1,int n,float *out,
                                        const WXGLensFollow *follow) {
    float r=WXG_MAX(.5f,WXG_MIN(bw,bh)*.5f),straight=WXG_MAX(0.f,bw*.5f-r);
    for(int side=0;side<2;side++)for(int i=0;i<n;i++) {
        float u=n>1?(float)i/(float)(n-1):0.f;
        float x=side==0?x0+(x1-x0)*u:x1+(x0-x1)*u;
        float dx=x-bx,s=dx<0.f?-1.f:1.f,over=WXG_ABS(dx)-straight;
        float qx,qy,nx,ny,sy=side==0?-1.f:1.f;
        if(over<=0.f){qx=x;qy=by+sy*r;nx=0.f;ny=sy;}
        else {
            float c=WXG_MIN(over,r),h=WXG_SQRT(WXG_MAX(0.f,r*r-c*c));
            qx=bx+s*(straight+c);qy=by+sy*h;nx=s*c/r;ny=sy*h/r;
        }
        WXGShapeSample l=WXGCapsuleOpticalField(qx-lx,qy-ly,lw,lh);
        float inset=WXGInnerInsetAlong(insetHeight,press,pinch,WXGLensDepthAlongBar(l.distance,-ny,nx,l.nx,l.ny));
        float d=WXG_MIN(inset+extra,r-.01f);   /* never past the middle: top and bottom don't cross */
        float px=qx-nx*d,py=qy-ny*d;
        if(follow && follow->margin>0.f)
            py=by+(py-by)*WXGLensBarZoom(px,bx,by,bw,bh,lx,ly,lw,lh,insetHeight,press,pinch,follow->side,follow->ratio,follow->sharpness,follow->margin);
        out[2*(side*n+i)]=px;out[2*(side*n+i)+1]=py;
    }
}
/* The material's edge fade (WXGMaterialOpacity: 1 - .82 * edge^2, edge the
   shader's wxgEdge over `width`) as k nested bands from the contour inward,
   band j from depth j * width / (k - 1) (the last covers the rest): the
   alpha of each band so that, composited over each other (one colour), the
   veil shows `alpha` * the fade at each band's middle depth (the full alpha
   past `width`). k = 1, or no width: one band of `alpha`. Returns k. */
static inline int WXGTravelVeilBands(float alpha,float width,int k,float *depth,float *bandAlpha) {
    float a=WXGOClamp(alpha,0.f,1.f);
    if(k<2 || !(width>.01f)){depth[0]=0.f;bandAlpha[0]=a;return 1;}
    float step=width/(float)(k-1),previous=0.f;
    for(int j=0;j<k;j++) {
        float level=1.f;
        if(j<k-1) {
            float t=WXGOClamp(((float)j+.5f)*step/width,0.f,1.f),edge=1.f-t*t*(3.f-2.f*t);
            level=1.f-.82f*edge*edge;
        }
        float target=a*level;
        depth[j]=(float)j*step;
        bandAlpha[j]=previous<1.f?WXGOClamp(1.f-(1.f-target)/(1.f-previous),0.f,1.f):0.f;
        previous=target;
    }
    return k;
}
#endif
