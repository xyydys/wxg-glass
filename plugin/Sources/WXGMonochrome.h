#ifndef WXG_MONOCHROME_H
#define WXG_MONOCHROME_H
#include <stdint.h>
#include <stddef.h>
static inline int WXGMonochromeRGBA(const uint8_t *pixels,size_t count) {
    unsigned ink=0,colored=0,low=255,high=0,core=0;
    for(size_t i=0;i<count;i++) {
        const uint8_t *p=pixels+i*4;if(p[3]<24)continue;++ink;
        unsigned hi=p[0]>p[1]?p[0]:p[1];if(p[2]>hi)hi=p[2];
        unsigned lo=p[0]<p[1]?p[0]:p[1];if(p[2]<lo)lo=p[2];
        if((hi-lo)*255>p[3]*24)++colored;
        if(p[3]>=128){unsigned lum=(p[0]+p[1]+p[2])*255/(3*p[3]);
            if(lum<low)low=lum;
            if(lum>high)high=lum;
            ++core;
        }
    }
    /* Preserve shaded grayscale artwork as artwork, not a filled silhouette. */
    return ink>0 && colored*100<=ink*2 && (!core || high-low<=52);
}
#endif
