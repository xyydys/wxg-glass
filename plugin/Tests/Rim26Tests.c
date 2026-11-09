/* FIX122 F / G: iOS 26 边框's per-pixel masks (Sources/WXGRim26.h). */
#include "../Sources/WXGRim26.h"
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

static WXGRim26Shape measured(void) {
    WXGRim26Shape s={.45,.25,.42,45,0,1,-.15,.15,0,.15,2.5};return s;
}
int main(void) {
    WXGRim26Shape s=measured();
    /* The line's profile as measured: peak at .45, the inner flank wider. */
    double best=0,at=0;for(double t=0;t<2;t+=.005){double v=WXGRim26Share(WXGRim26PartLine,t,s);if(v>best){best=v;at=t;}}
    CHECK(fabs(at-.45)<.01 && fabs(best-1)<1e-9,"peak at .45 (%.3f)",at);
    double hiIn=0,hiOut=0;
    for(double t=.45;t<2;t+=.001)if(WXGRim26Share(WXGRim26PartLine,t,s)>=.5)hiIn=t-.45;
    for(double t=.45;t>0;t-=.001)if(WXGRim26Share(WXGRim26PartLine,t,s)>=.5)hiOut=.45-t;
    CHECK(hiIn/hiOut>1.5 && hiIn/hiOut<1.8,"inner half-width / outer = %.2f",hiIn/hiOut);
    /* Lighter + deeper = the line: they only ever change the line's own colour, where it is. */
    for(double t=0;t<2.5;t+=.01) {
        double l=WXGRim26Share(WXGRim26PartLighter,t,s),d=WXGRim26Share(WXGRim26PartDeeper,t,s),line=WXGRim26Share(WXGRim26PartLine,t,s);
        CHECK(fabs(l+d-line)<1e-9 && l>=0 && d>=0,"lighter + deeper = the line at %.2f",t);
    }
    CHECK(WXGRim26Share(WXGRim26PartLighter,.2,s)>WXGRim26Share(WXGRim26PartDeeper,.2,s) &&
          WXGRim26Share(WXGRim26PartDeeper,.8,s)>WXGRim26Share(WXGRim26PartLighter,.8,s),"lighter outside the peak, deeper inside");
    CHECK(fabs(WXGRim26Share(WXGRim26PartShadow,0,s)-1)<1e-9 && fabs(WXGRim26Share(WXGRim26PartShadow,2.5,s)-exp(-1))<1e-9,"shadow: exponential");
    CHECK(WXGRim26Share(WXGRim26PartLine,-.1,s)==0,"nothing outside");

    /* Canvases: a round button whole; a capsule bar its ends and 2 pt of edge, stretched. */
    WXGRim26Canvas b=WXGRim26CanvasFor(44,44,22,WXGRim26PartReach(WXGRim26PartLine,s),3);
    CHECK(!b.stretchX && !b.stretchY && b.columns==132 && b.rows==132,"button: whole (%d x %d)",b.columns,b.rows);
    WXGRim26Canvas bar=WXGRim26CanvasFor(330,64,32,WXGRim26PartReach(WXGRim26PartLine,s),3);
    CHECK(bar.stretchX && !bar.stretchY && fabs(bar.width-68)<1e-9 && bar.rows==192,"bar: ends + 2 pt (%.1f x %.1f)",bar.width,bar.height);
    WXGRim26Canvas panel=WXGRim26CanvasFor(390,844,38,WXGRim26PartReach(WXGRim26PartShadow,s),3);
    CHECK(panel.stretchX && panel.stretchY && panel.columns*panel.rows<60000,"panel: corners only (%d x %d)",panel.columns,panel.rows);

    /* The button's pixels are the sketch's formula. */
    unsigned char *px=calloc((size_t)b.columns*b.rows,1);
    WXGRim26Fill(px,b.columns,b,22,3,WXGRim26PartLine,s,0,1);
    /* along the outline at constant depth: brightest top-left / bottom-right, none top-right / bottom-left */
    double cx=66,cy=66,rr=(22-.45)*3;
    int tl=px[(int)(cy-rr*sin(M_PI*.75))*b.columns+(int)(cx+rr*cos(M_PI*.75))];
    int br=px[(int)(cy+rr*sin(M_PI*.25))*b.columns+(int)(cx+rr*cos(M_PI*.25))];
    int tr=px[(int)(cy-rr*sin(M_PI*.25))*b.columns+(int)(cx+rr*cos(M_PI*.25))];
    int top=px[(int)(cy-rr)*b.columns+66];
    CHECK(tl>200 && br>200 && tr<15 && top>120 && top<tl,"along the outline: TL %d BR %d TR %d top %d",tl,br,tr,top);
    int centre=px[66*b.columns+66],outside=px[0];
    CHECK(centre==0 && outside==0,"nothing in the middle or outside");
    free(px);
    /* The bar's stretched columns are all alike (a straight edge). */
    unsigned char *pb=calloc((size_t)bar.columns*bar.rows,1);
    WXGRim26Fill(pb,bar.columns,bar,32,3,WXGRim26PartLine,s,0,1);
    int a0=(int)(bar.edgeX*3)+1,diff=0;
    for(int j=0;j<bar.rows;j++)for(int i=a0;i<a0+4;i++)diff+=abs(pb[j*bar.columns+i]-pb[j*bar.columns+a0]);
    CHECK(diff<=bar.rows/8,"stretch columns alike (%d)",diff);
    free(pb);
    /* Strength scales, the shadow has no direction. */
    unsigned char *ps=calloc((size_t)b.columns*b.rows,1);
    WXGRim26Fill(ps,b.columns,b,22,3,WXGRim26PartShadow,s,1,.5);
    int st=ps[3*b.columns+66],sr=ps[66*b.columns+(b.columns-1-3)];   /* the same depth from the top and from the right */
    CHECK(abs(st-sr)<=2 && st>40 && st<130,"shadow even all round, at half strength (%d %d)",st,sr);
    free(ps);

    if(failures){printf("Rim26Tests: %d failure(s)\n",failures);return 1;}
    printf("PASS: iOS 26 rim (FIX122 F/G): measured profile (peak .45, inner 1.6x wider), lighter + deeper = the line, shadow exponential; canvases (whole button, stretched bar, corner-only panel); pixels by the formula: brightest TL/BR, none TR/BL, nothing outside or in the middle; stretched columns alike; strength.\n");
    return 0;
}
