/* FIX58: the clear-ring mask built only along the outline (WXGFillRingMask)
   has exactly the bytes of evaluating WXGSharpRingAlpha at every pixel (the
   FIX57 loop in WXGGlassView updateEdgeMask), for rounded and capsule glass,
   every edge width / coverage, 1x and 2x; and it skips most of a large card. */
#include "../Sources/WXGEdgeMaskBand.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void reference(uint8_t *bytes,size_t w,size_t h,size_t stride,float scale,const float key[5]) {
    for(size_t j=0;j<h;j++)for(size_t i=0;i<w;i++) {
        float alpha=WXGSharpRingAlpha(((float)i+.5f)/scale,((float)j+.5f)/scale,key[0],key[1],key[2],key[3],key[4]);
        bytes[j*stride+i]=(uint8_t)lroundf(255.f*alpha);
    }
}
static unsigned long evaluated(size_t w,size_t h,float scale,const float key[5]) {
    float corner=WXGRingFieldRadius(key[0],key[1],key[2])+1.f,clear=key[3]+1.f;unsigned long n=0;
    for(size_t j=0;j<h;j++)for(size_t i=0;i<w;i++)
        if(!WXGRingMaskSkips(((float)i+.5f)/scale,((float)j+.5f)/scale,key[0],key[1],corner,clear))++n;
    return n;
}
static unsigned long cases,nonzero;
static double check(float width,float height,float radius,float edge,float coverage,float scale) {
    float key[5]={width,height,radius,edge,coverage};
    size_t w=(size_t)ceil(width*scale),h=(size_t)ceil(height*scale),stride=w+3;   /* padded rows like CGBitmapContext */
    uint8_t *a=malloc(stride*h),*b=malloc(stride*h);
    assert(a && b);
    memset(a,0xA5,stride*h);memset(b,0xA5,stride*h);
    reference(a,w,h,stride,scale,key);
    WXGFillRingMask(b,w,h,stride,scale,key);
    for(size_t j=0;j<h;j++) {
        if(memcmp(a+j*stride,b+j*stride,w)!=0) {
            for(size_t i=0;i<w;i++)if(a[j*stride+i]!=b[j*stride+i])
                fprintf(stderr,"mismatch %.2fx%.2f r%.2f e%.2f c%.2f s%.0f at %zu,%zu: %u vs %u\n",width,height,radius,edge,coverage,scale,i,j,a[j*stride+i],b[j*stride+i]);
            assert(0);
        }
        for(size_t i=w;i<stride;i++)assert(b[j*stride+i]==0xA5);   /* nothing written past the row */
        for(size_t i=0;i<w;i++)if(a[j*stride+i])++nonzero;
    }
    free(a);free(b);++cases;
    return (double)evaluated(w,h,scale,key)/(double)(w*h);
}
int main(void) {
    /* The settings cards (XS Max, card radius 26, default edge 10 / coverage 0). */
    double home=check(182.1818f,113,26,10,0,2),header=check(376.3636f,86,26,10,0,2);
    double lens=check(376.3636f,350,26,10,0,2),tall=check(376.3636f,700,26,10,0,2);
    /* WeChat glass: buttons and capsules (radius 0), the dock, a menu, an input. */
    check(41.4f,41.4f,0,10,0,3);check(120,41.4f,0,10,0,2);check(380,68,0,20.26f,0,2);
    check(250,300,18,10,0,2);check(300,40,20,10,.35f,2);check(41.4f,41.4f,20.7f,10,0,2);
    /* Boundaries: radius 0.5 / over half the height, edge 1 / 60, coverage 0..1, odd sizes. */
    check(200,120,.5f,1,0,2);check(200,120,500,10,0,2);check(200,120,26,60,0,2);check(200,120,26,10,1,2);
    check(3,3,26,10,0,2);check(2.2f,97.7f,0,1,0,1);check(97.7f,2.2f,40,59.9f,.999f,2);
    unsigned seed=58;
    for(int n=0;n<260;n++) {
        seed=seed*1103515245u+12345u;float u1=(float)((seed>>8)&0xFFFF)/65535.f;
        seed=seed*1103515245u+12345u;float u2=(float)((seed>>8)&0xFFFF)/65535.f;
        seed=seed*1103515245u+12345u;float u3=(float)((seed>>8)&0xFFFF)/65535.f;
        seed=seed*1103515245u+12345u;float u4=(float)((seed>>8)&0xFFFF)/65535.f;
        seed=seed*1103515245u+12345u;float u5=(float)((seed>>8)&0xFFFF)/65535.f;
        float width=2+u1*398,height=2+u2*398;
        float radius=n%5==0?0:u3*90;
        float edge=1+u4*59,coverage=n%4==0?0:n%7==0?1:u5;
        check(width,height,radius,edge,coverage,n%3==0?1.f:2.f);
    }
    assert(nonzero>0);
    /* A big card evaluates a small part of its pixels. */
    assert(lens<.16 && tall<.10 && home<.40 && header<.45);
    printf("PASS: clear-ring mask along the outline only: %lu shapes byte-identical to the full evaluation (rounded, capsule, coverage 0..1, 1x/2x); "
           "settings cards evaluate %.0f%% (182x113), %.0f%% (376x86), %.0f%% (376x350), %.0f%% (376x700) of their pixels.\n",
           cases,home*100,header*100,lens*100,tall*100);
    return 0;
}
