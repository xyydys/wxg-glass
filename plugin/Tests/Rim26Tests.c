/* FIX123: iOS 26 边框, the system's own recipe (Sources/WXGRim26.h), against
   what GlassProbe captured on iOS 26.6 (8x captures, 24 px per point). */
#include "../Sources/WXGRim26.h"
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

static WXGRim26Shape systems(double ring) {
    WXGRim26Shape s={1,.7,45,1.05,1,1,ring,2.5};return s;
}
static double luma(const double c[3]) {return .2126*c[0]+.7152*c[1]+.0722*c[2];}
int main(void) {
    WXGRim26Shape s=systems(.04);
    /* Across the edge: brightest at the outline, a straight line to 30 % at 1 pt, cut hard there. */
    CHECK(fabs(WXGRim26Across(0,s)-1)<1e-12 && fabs(WXGRim26Across(.5,s)-.65)<1e-12 && fabs(WXGRim26Across(1,s)-.3)<1e-12,"1 -> .30 over the height");
    CHECK(WXGRim26Across(1.001,s)==0 && WXGRim26Across(-.001,s)==0,"nothing past the height or outside");
    /* Along the outline: |cos| about the lower right / upper left; none at the upper right / lower left. */
    double q=sqrt(.5);
    CHECK(fabs(WXGRim26Along(q,q,s)-1)<1e-9 && fabs(WXGRim26Along(-q,-q,s)-1)<1e-9,"key lower right (1.05, capped at 1), fill upper left 1");
    CHECK(WXGRim26Along(q,-q,s)<1e-9 && WXGRim26Along(-q,q,s)<1e-9,"none upper right / lower left");
    CHECK(fabs(WXGRim26Along(1,0,s)-1.05*q)<1e-9 && fabs(WXGRim26Along(0,1,s)-1.05*q)<1e-9 && fabs(WXGRim26Along(-1,0,s)-q)<1e-9 && fabs(WXGRim26Along(0,-1,s)-q)<1e-9,"the sides at cos 45");
    {WXGRim26Shape t=s;t.angle=0;CHECK(fabs(WXGRim26Along(0,1,t)-1)<1e-9 && WXGRim26Along(1,0,t)<1e-9,"angle 0: bottom / top");
     t.angle=90;CHECK(fabs(WXGRim26Along(1,0,t)-1)<1e-9 && WXGRim26Along(0,1,t)<1e-9,"angle 90: the ends");
     t.angle=45;t.spread=3;CHECK(fabs(WXGRim26Along(-1,0,t)-q*q*q)<1e-9,"spread: the lobes' exponent");}
    /* The faint line all round: full to a third, gone by two thirds; laid over the lights, never past 1. */
    CHECK(fabs(WXGRim26Ring(.2,s)-.04)<1e-12 && fabs(WXGRim26Ring(.5,s)-.02)<1e-12 && WXGRim26Ring(.7,s)==0,"ring: full to 1/3, gone by 2/3");
    CHECK(fabs(WXGRim26Alpha(.2,q,-q,s)-.04)<1e-9,"where the lights are out: the ring alone");
    for(double d=0;d<=1;d+=.05)for(int a=0;a<360;a+=5){double v=WXGRim26Alpha(d,cos(a*M_PI/180),sin(a*M_PI/180),systems(1));CHECK(v>=0 && v<=1,"alpha in 0..1");}

    /* The dark matrix is the one dumped from the system's vibrantColorMatrix. */
    float dark[20],light[20];WXGRim26Matrix(1.35,3.0,.15,dark);WXGRim26Matrix(.174,1.51,.847,light);
    static const float dumped[15]={2.6492f,-1.1803f,-.1189f,0,.15f, -.3507f,1.8199f,-.1192f,0,.15f, -.3509f,-1.1799f,2.8809f,0,.15f};
    for(int i=0;i<15;i++)CHECK(fabs(dark[i]-dumped[i])<6e-4,"dark matrix[%d] %.4f, dumped %.4f",i,dark[i],dumped[i]);
    CHECK(dark[18]==1 && dark[15]==0 && dark[19]==0,"alpha kept");

    /* The captured glass button over slate, dark: face (37.4, 42, 47.1); luminance at
       depths .125 .25 .5 .75 .9 pt along four directions (degrees, counter-clockwise from the right). */
    {
        static const double depth[5]={.125,.25,.5,.75,.9};
        static const struct {int angle;double seen[5];} rows[]={
            {315,{91.9,87.4,77.8,67.7,61.9}},{135,{89.8,85.2,75.3,65.3,59.9}},
            {0,{77.2,74.0,67.2,59.6,55.7}},{90,{76.1,73.0,65.6,58.4,54.7}},
            {45,{43.4,43.3,42.8,41.9,41.8}},{225,{43.3,43.4,42.7,41.9,41.7}}};
        const double face[3]={37.4/255,42./255,47.1/255};
        double worst=0;
        for(size_t r=0;r<sizeof rows/sizeof *rows;r++)for(int i=0;i<5;i++) {
            double a=rows[r].angle*M_PI/180,out[3];
            WXGRim26Colour(dark,face,WXGRim26Alpha(depth[i],cos(a),-sin(a),s),out);   /* y down */
            double e=fabs(luma(out)*255-rows[r].seen[i]);if(e>worst)worst=e;
        }
        CHECK(worst<2.5,"dark button over slate: within %.1f levels of the capture",worst);
        double out[3];WXGRim26Colour(dark,face,WXGRim26Alpha(1.1,q,q,s),out);
        CHECK(fabs(luma(out)*255-41.4)<.2,"past 1 pt: the face itself");
    }
    /* Light glass, the grey 50 % button (face 205.5) all round, .125 pt in (captured):
       lower right, upper left, right, upper right. */
    {
        WXGRim26Shape l=systems(.13);
        const double face[3]={205.5/255,205.5/255,205.5/255};double out[3];
        WXGRim26Colour(light,face,WXGRim26Alpha(.125,q,q,l),out);CHECK(fabs(out[0]*255-248.3)<2.5,"light, lower right %.1f (248.3)",out[0]*255);
        WXGRim26Colour(light,face,WXGRim26Alpha(.125,-q,-q,l),out);CHECK(fabs(out[0]*255-246.5)<2.5,"light, upper left %.1f (246.5)",out[0]*255);
        WXGRim26Colour(light,face,WXGRim26Alpha(.125,1,0,l),out);CHECK(fabs(out[0]*255-237.4)<2.5,"light, right %.1f (237.4)",out[0]*255);
        WXGRim26Colour(light,face,WXGRim26Alpha(.125,q,-q,l),out);CHECK(fabs(out[0]*255-212.7)<2.5,"light, upper right %.1f (212.7)",out[0]*255);
    }
    /* Dark glass on colours: red stays red (clamped), grey stays grey. */
    {
        double red[3]={167./255,2./255,2./255},grey[3]={88.4/255,88.3/255,88.3/255},out[3];
        WXGRim26Colour(dark,red,1,out);CHECK(out[0]==1 && out[1]==0 && out[2]==0,"dark over red: clamped pure red");
        WXGRim26Colour(dark,grey,1,out);CHECK(fabs(out[0]*255-157.7)<.5 && fabs(out[0]-out[2])<.01,"dark over grey 88: 157.7 (%.1f)",out[0]*255);
        WXGRim26Colour(dark,grey,0,out);CHECK(out[0]==grey[0],"no alpha: the face");
    }

    /* Canvases: a round button whole; a capsule bar its ends and 2 pt of edge, stretched. */
    WXGRim26Canvas b=WXGRim26CanvasFor(44,44,22,WXGRim26PartReach(WXGRim26PartLine,s),3);
    CHECK(!b.stretchX && !b.stretchY && b.columns==132 && b.rows==132,"button: whole (%d x %d)",b.columns,b.rows);
    WXGRim26Canvas bar=WXGRim26CanvasFor(330,64,32,WXGRim26PartReach(WXGRim26PartLine,s),3);
    CHECK(bar.stretchX && !bar.stretchY && fabs(bar.width-68)<1e-9 && bar.rows==192,"bar: ends + 2 pt (%.1f x %.1f)",bar.width,bar.height);
    WXGRim26Canvas panel=WXGRim26CanvasFor(390,844,38,WXGRim26PartReach(WXGRim26PartShadow,s),3);
    CHECK(panel.stretchX && panel.stretchY && panel.columns*panel.rows<60000,"panel: corners only (%d x %d)",panel.columns,panel.rows);

    /* The button's pixels at 3x: three pixels of rim, brightest outermost, nothing inside or outside. */
    unsigned char *px=calloc((size_t)b.columns*b.rows,1);
    WXGRim26Fill(px,b.columns,b,22,3,WXGRim26PartLine,s,0);
    {
        int n=0,beyond=0;
        for(int j=0;j<b.rows;j++)for(int i=0;i<b.columns;i++) {
            double x=(i+.5)/3-22,y=(j+.5)/3-22,d=22-sqrt(x*x+y*y);
            if(px[j*b.columns+i]){++n;if(d>1+.5 || d<-.5)++beyond;}
        }
        CHECK(n>300 && beyond==0,"all of it within the 1 pt band (%d pixels, %d beyond)",n,beyond);
        /* the right side's middle row, from the outline inward: three pixels, then nothing */
        int v[5];for(int k=0;k<5;k++)v[k]=px[66*b.columns+(b.columns-1-k)];
        CHECK(abs(v[0]-169)<=6 && abs(v[1]-126)<=6 && abs(v[2]-79)<=6 && v[3]==0 && v[4]==0,"right side: %d %d %d | %d %d",v[0],v[1],v[2],v[3],v[4]);
        double rr=(22-.5)*3;
        int tl=px[(int)(66-rr*q)*b.columns+(int)(66-rr*q)],br=px[(int)(66+rr*q)*b.columns+(int)(66+rr*q)];
        int tr=px[(int)(66-rr*q)*b.columns+(int)(66+rr*q)],top=px[(int)(66-rr)*b.columns+66];
        CHECK(br>=tl && tl>.9*br && tr<16 && top>.55*tl && top<.85*tl,"along the outline: TL %d BR %d TR %d top %d",tl,br,tr,top);
        CHECK(px[66*b.columns+66]==0 && px[0]==0,"nothing in the middle or outside");
    }
    /* With a pixel of bleed (the layer is then clipped by the glass' own corner): the same
       inside, the outline's own level carried one pixel past it. */
    {
        unsigned char *pe=calloc((size_t)b.columns*b.rows,1);
        WXGRim26Fill(pe,b.columns,b,22,3,WXGRim26PartLine,s,1);
        int same=1,more=0,far=0;
        for(int j=0;j<b.rows;j++)for(int i=0;i<b.columns;i++) {
            double x=(i+.5)/3-22,y=(j+.5)/3-22,d=22-sqrt(x*x+y*y);
            if(d>.25 && pe[j*b.columns+i]!=px[j*b.columns+i])same=0;
            if(d<0 && d>-.3 && pe[j*b.columns+i]>px[j*b.columns+i])++more;
            if(d<-.75 && pe[j*b.columns+i])++far;
        }
        double rr=22*3+.2;int edge=pe[(int)(66+rr*q)*b.columns+(int)(66+rr*q)];
        CHECK(same && more>100 && far==0 && edge>200,"bleed: inside unchanged, a pixel past the outline lit (%d pixels, at the lower right %d), none further (%d)",more,edge,far);
        free(pe);
    }
    free(px);
    /* The bar's stretched columns are all alike (a straight edge). */
    unsigned char *pb=calloc((size_t)bar.columns*bar.rows,1);
    WXGRim26Fill(pb,bar.columns,bar,32,3,WXGRim26PartLine,s,0);
    int a0=(int)(bar.edgeX*3)+1,diff=0,lit=0;
    for(int j=0;j<bar.rows;j++)for(int i=a0;i<a0+4;i++){diff+=abs(pb[j*bar.columns+i]-pb[j*bar.columns+a0]);lit+=pb[j*bar.columns+i]>0;}
    CHECK(diff==0 && lit==4*6,"stretch columns alike (%d), 3 px of rim top and bottom (%d)",diff,lit);
    free(pb);
    /* The optional shadow: exponential, the same all round. */
    CHECK(fabs(WXGRim26Shadow(0,s)-1)<1e-12 && fabs(WXGRim26Shadow(2.5,s)-exp(-1))<1e-12 && WXGRim26Shadow(-.1,s)==0,"shadow: exponential from the outline");
    unsigned char *ps=calloc((size_t)b.columns*b.rows,1);
    WXGRim26Fill(ps,b.columns,b,22,3,WXGRim26PartShadow,s,0);
    int st=ps[3*b.columns+66],sr=ps[66*b.columns+(b.columns-1-3)];   /* the same depth from the top and from the right */
    CHECK(abs(st-sr)<=2 && st>120 && st<200,"shadow even all round (%d %d)",st,sr);
    free(ps);

    if(failures){printf("Rim26Tests: %d failure(s)\n",failures);return 1;}
    printf("PASS: iOS 26 rim (FIX123, the system's recipe): 1 -> .30 over 1 pt then cut; |cos| about lower right / upper left; ring where the lights are out; dark matrix = the dumped one; dark button over slate and the light grey button all round match the captures; canvases; pixels within the 1 pt band, 3 px at 3x; bleed past the outline for the clipped layer; stretched columns alike; shadow.\n");
    return 0;
}
