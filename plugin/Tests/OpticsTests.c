#include "../Sources/WXGOptics.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    const float widths[]={208,280,360,420},heights[]={54,68,90};
    for(unsigned wi=0;wi<4;wi++) for(unsigned hi=0;hi<3;hi++) {
        float w=widths[wi],h=heights[hi],r=h*.5f,join=w*.5f-r;
        assert(WXGCapsuleOpticalField(0,0,w,h).distance<0);
        assert(fabsf(WXGCapsuleOpticalField(w*.5f,0,w,h).distance)<.001f);
        assert(fabsf(WXGCapsuleOpticalField(0,r,w,h).distance)<.001f);
        assert(WXGCapsuleOpticalField(w*.5f+1,0,w,h).distance>0);
        // FIX96: the outline is Core Animation's continuous capsule: each point
        // of the circular end moved out along its normal by R x the deviation.
        for(int k=0;k<=100;k++) {
            float t=k/100.f;
            float x=join+r*t,y=r*sqrtf(1-t*t),phi=atan2f(x-join,y),dev=r*WXGContinuousDeviation(phi);
            float ox=x+t*dev,oy=y+sqrtf(1-t*t)*dev;
            WXGShapeSample a=WXGCapsuleOpticalField(ox,oy,w,h),b=WXGCapsuleOpticalField(-ox,-oy,w,h);
            assert(fabsf(a.distance)<.004f*r);
            assert(fabsf(a.distance-b.distance)<.002f);
            assert(isfinite(a.nx) && isfinite(a.ny));
        }
        float fullyPressed=WXGLensHeight(h,6,1,1.28f,0);
        float inner=h-2*WXGInnerInset(h,1,.18f,-10);
        assert(fullyPressed>h*1.27f && inner<h*.83f && inner>h*.81f);
        // FIX47: the inset ramps over as many points as it is deep (~45 degrees):
        // full beyond that depth, exactly half at half of it, never decreasing.
        {float full=WXGInnerInset(h,1,.30f,-200);
         assert(fabsf(WXGInnerInset(h,1,.30f,-(full+1))-full)<.0001f);
         assert(fabsf(WXGInnerInset(h,1,.30f,-full*.5f)-full*.5f)<.0001f);
         float last=0;for(int k=0;k<=40;k++){float v=WXGInnerInset(h,1,.30f,-full*k/40.f);assert(v+1e-5f>=last);last=v;}}
        assert(WXGInnerInset(h,0,.30f,-10)==0);
        // Largest supported outer lens, including whole-bar growth, fits its canvas.
        assert((WXGLensHeight(h,6,1,1.5f,0)*1.08f-h)*.5f<WXGCanvasPaddingY);
        // Sample the actual shared distance/normal/remap functions. The central
        // legacy vertical ray must remain ordered in its original 0..2 range.
        // This ordering assertion does not extend to the larger trial range.
        for(int ei=3;ei<=14;ei++) for(int zi=10;zi<=15;zi++) {
            float zoom=zi/10.f,lensH=WXGLensHeight(h,6,1,1.5f,0),last=-10000;
            for(int yi=-500;yi<=500;yi++) {
                float y=yi/500.f*lensH*.5f;
                WXGShapeSample q=WXGCapsuleOpticalField(0,y,lensH*1.25f,lensH);
                float source=y/zoom-q.ny*WXGOpticalOffset(q.distance,(float)ei,2)/zoom;
                assert(isfinite(source)); assert(source>last); last=source;
            }
        }
    }
    assert(WXGCaptureScale(3)==3 && WXGCaptureScale(2)==2);
    for(int si=0;si<=144;si++) {
        float sigma=si*.25f; WXGGaussianKernel k=WXGMakeGaussian(sigma);
        assert(k.count>=0 && k.count<=54);
        double discrete[109]={0}; discrete[0]=k.center;
        for(int i=0;i<k.count;i++) {
            int base=(int)floorf(k.offsets[i]); float part=k.offsets[i]-base;
            assert(base>=1 && base<=108);
            discrete[base]+=k.weights[i]*(1-part);
            if(part>0) { assert(base<108); discrete[base+1]+=k.weights[i]*part; }
        }
        double total=discrete[0];
        for(int j=1;j<=108;j++) total+=2*discrete[j];
        assert(fabs(total-1)<.00001);
        if(sigma>.05f) {
            // Compare every reconstructed paired tap against a dense Gaussian,
            // preventing sparse-sampling stripes or duplicated text silhouettes.
            int radius=(int)ceilf(3*sigma); double norm=1;
            for(int j=1;j<=radius;j++) norm+=2*exp(-.5*j*j/(sigma*sigma));
            for(int j=0;j<=radius;j++) assert(fabs(discrete[j]-exp(-.5*j*j/(sigma*sigma))/norm)<.00001);
        }
    }
    puts("PASS: capsule optical distance, finite normals, symmetry, outer growth, uniform inner inset, unclipped extent, non-folding rays, native scale, dense Gaussian pairing.");
    return 0;
}
