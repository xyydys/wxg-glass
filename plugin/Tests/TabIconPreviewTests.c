#include "../Sources/WXGTabIconPreview.h"
#include <assert.h>
#include <stdio.h>

enum { w=32,h=32 };
static uint8_t input[w*h*4],preview[w*h*4];
static uint8_t *pixel(uint8_t *image,int x,int y) {return image+4*(y*w+x);}
static void ink(int x,int y,uint8_t r,uint8_t g,uint8_t b) {
    uint8_t *p=pixel(input,x,y);p[0]=r;p[1]=g;p[2]=b;p[3]=255;
}
static void rectangle(int left,int right,int top,int bottom,uint8_t r,uint8_t g,uint8_t b) {
    for(int x=left;x<=right;x++){ink(x,top,r,g,b);ink(x,bottom,r,g,b);}
    for(int y=top;y<=bottom;y++){ink(left,y,r,g,b);ink(right,y,r,g,b);}
}
int main(void) {
    // An outlined gear with a second, isolated ring around its central hole.
    rectangle(4,27,4,27,25,25,25);rectangle(12,20,12,20,25,25,25);
    assert(WXGFillTabIcon(input,preview,w,h,true));
    assert(pixel(preview,3,14)[3]==0 && pixel(preview,8,14)[3]==255);
    assert(pixel(preview,12,15)[3]==0 && pixel(preview,13,15)[3]==0);
    // Contacts/telephone glyphs can use open strokes. The selected branch
    // thickens the incoming artwork and keeps its visible extents.
    memset(input,0,sizeof input);
    for(int i=5;i<27;i++)ink(i,i,10,10,10);
    assert(WXGFillTabIcon(input,preview,w,h,true));
    assert(pixel(preview,7,8)[3]>0 && pixel(preview,3,5)[3]==0 && pixel(preview,4,5)[3]==0);
    // A two-colour theme keeps all original fully covered pixels, including
    // a coloured emblem. The transparent interior takes the contour's ink.
    memset(input,0,sizeof input);
    rectangle(3,29,3,29,200,40,20);rectangle(13,21,12,19,20,160,200);
    uint8_t original[sizeof input];memcpy(original,input,sizeof input);
    assert(WXGFillTabIcon(input,preview,w,h,false));
    assert(!memcmp(input,original,sizeof input));
    for(int i=0;i<w*h;i++)if(input[4*i+3]==255)assert(!memcmp(input+4*i,preview+4*i,4));
    assert(pixel(preview,8,8)[0]==200 && pixel(preview,8,8)[3]==255);
    assert(pixel(preview,0,18)[3]==0);
    memset(input,0,sizeof input); assert(!WXGFillTabIcon(input,preview,w,h,true));
    assert(!WXGFillTabIcon(input,preview,161,h,true));
    puts("PASS: unseen tab selection fills its own glyph, preserves cutouts, open strokes and theme colour; normal bitmap is untouched.");
}
