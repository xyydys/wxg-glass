#ifndef WXG_DISTANCE_FIELD_H
#define WXG_DISTANCE_FIELD_H
#include <math.h>
#include <stdlib.h>
#include <stdint.h>
// Separable squared Euclidean distance transform. The lower envelope of
// parabolas avoids a radius-dependent search and is linear in pixel count.
static inline void WXGDistanceLine(const float *f,float *d,int n,int *v,float *z) {
    int k=-1;
    for(int q=0;q<n;q++) {
        if(f[q]>=1e11f) continue;
        float s=-1e30f;
        while(k>=0) {
            int vk=v[k];
            s=((f[q]+q*(float)q)-(f[vk]+vk*(float)vk))/(2.f*(q-vk));
            if(s>z[k]) break;
            --k;
        }
        ++k; v[k]=q; z[k]=k==0?-1e30f:s; z[k+1]=1e30f;
    }
    if(k<0) { for(int q=0;q<n;q++) d[q]=1e12f; return; }
    k=0;
    for(int q=0;q<n;q++) {
        while(z[k+1]<q) ++k;
        float x=q-v[k]; d[q]=x*x+f[v[k]];
    }
}
static inline void WXGDistancePass(float *pixels,int w,int h,float *f,float *d,int *v,float *z) {
    for(int y=0;y<h;y++) { WXGDistanceLine(pixels+y*w,d,w,v,z); for(int x=0;x<w;x++) pixels[y*w+x]=d[x]; }
    for(int x=0;x<w;x++) {
        for(int y=0;y<h;y++) f[y]=pixels[y*w+x];
        WXGDistanceLine(f,d,h,v,z);
        for(int y=0;y<h;y++) pixels[y*w+x]=d[y];
    }
}
// Alpha is the actual native continuous silhouette in top-left row order.
// Output is negative inside and expressed in screen points, not pixels.
static inline int WXGMakeNativeDistance(const uint8_t *alpha,int w,int h,float scale,float *out) {
    if(!alpha || !out || w<1 || h<1 || scale<=0) return 0;
    size_t count=(size_t)w*h; int n=w>h?w:h; size_t inside=0;
    float *other=(float *)malloc(count*sizeof(float));
    float *f=(float *)malloc((size_t)n*sizeof(float)),*d=(float *)malloc((size_t)n*sizeof(float));
    int *v=(int *)malloc((size_t)n*sizeof(int)); float *z=(float *)malloc(((size_t)n+1)*sizeof(float));
    if(!other || !f || !d || !v || !z) { free(other);free(f);free(d);free(v);free(z);return 0; }
    for(size_t i=0;i<count;i++) {
        int in=alpha[i]>=128; inside+=in; out[i]=in?0:1e12f;other[i]=in?1e12f:0;
    }
    if(inside==0 || inside==count) { free(other);free(f);free(d);free(v);free(z);return 0; }
    WXGDistancePass(out,w,h,f,d,v,z); WXGDistancePass(other,w,h,f,d,v,z);
    for(size_t i=0;i<count;i++) {
        float value=alpha[i]>=128?-(sqrtf(other[i])-.5f):sqrtf(out[i])-.5f;
        if(alpha[i]>0 && alpha[i]<255) value=.5f-alpha[i]/255.f;
        out[i]=value/scale;
    }
    free(other);free(f);free(d);free(v);free(z);return 1;
}
#endif
