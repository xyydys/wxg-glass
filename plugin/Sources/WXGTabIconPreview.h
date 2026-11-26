#ifndef WXG_TAB_ICON_PREVIEW_H
#define WXG_TAB_ICON_PREVIEW_H

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Input and output are premultiplied RGBA. Only used for a tab whose real
// selected artwork has not been seen. Keep the exterior and the emblem of
// the actual theme glyph (e.g. a compass needle or the hole in a gear).
static inline void WXGTabInkBehind(uint8_t *dst, const uint8_t *ink, unsigned alpha) {
    if (!ink[3] || dst[3] == 255) return;
    unsigned added = ((255-dst[3])*alpha+127)/255;
    for (int k=0;k<3;k++) dst[k]+=(uint8_t)((added*ink[k]+ink[3]/2)/ink[3]);
    dst[3]+=(uint8_t)added;
}

static inline bool WXGFillTabIcon(const uint8_t *src, uint8_t *dst, int w, int h, bool mono) {
    if (!src || !dst || w<2 || h<2 || w>160 || h>160) return false;
    enum { outside=1, shell=2, interior=3 };
    int n=w*h, count=0;
    uint8_t *kind=calloc((size_t)n,1);
    int *queue=malloc((size_t)n*sizeof(*queue));
    if (!kind || !queue) {free(kind);free(queue);return false;}
    memcpy(dst,src,(size_t)n*4);
    int left=w,top=h,right=-1,bottom=-1;
    const int dx[]={-1,1,0,0,-1,-1,1,1}, dy[]={0,0,-1,1,-1,1,-1,1};
    // Each region starts at the preceding region's boundary. Ink uses eight
    // neighbours, background four, so a diagonal outline stays connected.
    for (int region=outside;region<=interior;region++) {
        count=0;
        for (int y=0;y<h;y++) for (int x=0;x<w;x++) {
            int p=y*w+x;
            bool ink=src[4*p+3]>=64;
            bool edge=x==0 || y==0 || x==w-1 || y==h-1;
            if (region==outside && ink) {
                if (x<left) left=x;
                if (x>right) right=x;
                if (y<top) top=y;
                if (y>bottom) bottom=y;
            }
            if (kind[p] || ink!=(region==shell)) continue;
            if (edge && region!=interior) {kind[p]=region;queue[count++]=p;continue;}
            if (region==outside) continue;
            for (int k=0;k<4;k++) {
                int nx=x+dx[k],ny=y+dy[k];
                if (nx<0 || nx>=w || ny<0 || ny>=h) continue;
                int q=ny*w+nx;
                if (kind[q]!=region-1) continue;
                kind[p]=region;queue[count++]=p;
                if (region==interior) WXGTabInkBehind(dst+4*p,src+4*q,255);
                break;
            }
        }
        for (int i=0;i<count;i++) {
            int base=queue[i], x=base%w, y=base/w;
            for (int k=0;k<(region==shell?8:4);k++) {
                int nx=x+dx[k],ny=y+dy[k];
                if (nx<0 || nx>=w || ny<0 || ny>=h) continue;
                int p=ny*w+nx;
                if (kind[p] || (src[4*p+3]>=64)!=(region==shell)) continue;
                kind[p]=region;queue[count++]=p;
                if (region==interior) WXGTabInkBehind(dst+4*p,dst+4*base,255);
            }
        }
    }
    if (count && mono) {
        // In a filled monochrome glyph the enclosed emblem becomes a cutout.
        for (int p=0;p<n;p++) if (kind[p]==0) memset(dst+4*p,0,4);
    } else if (!count && right>=left) {
        // An open glyph has no enclosed space to fill. Give it a heavier
        // stroke inside its original ink bounds, retaining multicolour ink.
        int r=(int)fmax(1.,round(fmin(right-left+1,bottom-top+1)/32.));
        for (int y=top;y<=bottom;y++) for (int x=left;x<=right;x++) {
            int p=y*w+x, best=p;
            if (src[4*p+3]==255) continue;
            for (int j=-r;j<=r;j++) for (int i=-r;i<=r;i++) {
                int nx=x+i,ny=y+j;
                if (i*i+j*j>r*r || nx<left || nx>right || ny<top || ny>bottom) continue;
                int q=ny*w+nx;
                if (src[4*q+3]>src[4*best+3]) best=q;
            }
            if (best!=p) WXGTabInkBehind(dst+4*p,src+4*best,src[4*best+3]);
        }
    }
    free(queue);free(kind);
    return right>=left;
}
#endif
