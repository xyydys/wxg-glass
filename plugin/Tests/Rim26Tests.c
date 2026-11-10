/* FIX123 - FIX125: iOS 26 边框, the system's own recipe (Sources/WXGRim26.h), against
   what GlassProbe captured on iOS 26.6 (8x captures, 24 px per point). */
#include "../Sources/WXGRim26.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
    /* FIX130: an exponent below 1 no longer leaves a sharp dark nick where
       the two lights meet (lower left / upper right): the lights stay on
       across it, the more the lower the exponent, and turn round it smoothly;
       1 is the system's |cos| exactly, as before. */
    {WXGRim26Shape t=s;t.angle=45;const double q=sqrt(.5);
     for(int k=0;k<=40;k++){double a=k*M_PI/20,nx=cos(a),ny=sin(a),c=nx*q+ny*q;t.spread=1;
        CHECK(fabs(WXGRim26Along(nx,ny,t)-(c>0?WXGRim26Clamp(t.key*c,0,1):t.fill*-c))<1e-9,"spread 1: |cos| (at %d)",k);}
     const double spreads[3]={.3,.6,.9};
     for(int i=0;i<3;i++) {
        t.spread=spreads[i];
        double null=WXGRim26Along(q,-q,t),low=1,last=-1,steepest=0;   /* (q, -q): the upper right, square to both lights */
        CHECK(null>.05 && fabs(null-.85*(1-spreads[i])*(t.key+t.fill)*.5)<.02,"spread %.1f: lit at the null (%.3f)",spreads[i],null);
        CHECK(fabs(WXGRim26Along(-q,q,t)-null)<1e-9,"and the same at the lower left");
        for(int k=-200;k<=200;k++) {   /* across the null, a degree at a time and finer */
            double a=-M_PI/4+k*M_PI/1800.,v=WXGRim26Along(cos(a),sin(a),t);
            if(v<low)low=v;
            if(last>=0 && fabs(v-last)>steepest)steepest=fabs(v-last);
            last=v;
        }
        CHECK(low>.75*null,"spread %.1f: never darker than about its null (%.3f against %.3f)",spreads[i],low,null);
        CHECK(steepest<.012,"spread %.1f: no jump across the null (%.4f per 0.1 degree)",spreads[i],steepest);
        CHECK(fabs(WXGRim26Along(q,q,t)-WXGRim26Clamp(t.key,0,1))<1e-9 && fabs(WXGRim26Along(-q,-q,t)-t.fill)<1e-9,"spread %.1f: full at the two lights",spreads[i]);
     }
     t.spread=.999;CHECK(fabs(WXGRim26Along(1,0,t)-t.key*q)<.01,"just under 1: as 1");}
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
    CHECK(bar.stretchX && !bar.stretchY && fabs(bar.width-106.4)<1e-9 && bar.rows==192 && bar.realWidth==330,"bar: ends (1.6 r each) + 2 pt (%.1f x %.1f)",bar.width,bar.height);
    WXGRim26Canvas panel=WXGRim26CanvasFor(390,844,38,WXGRim26PartReach(WXGRim26PartShadow,s),3);
    CHECK(panel.stretchX && panel.stretchY && panel.columns*panel.rows<150000,"panel: corners only (%d x %d)",panel.columns,panel.rows);

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
    /* FIX124: the bar's ends are the real capsule's (continuous), not a small round canvas': its
       field is the 330 x 64 capsule's at the same distance from the end. */
    {
        double worst=0;
        for(double y=-31;y<=31;y+=2.)for(double xe=0;xe<52;xe+=2.) {   /* xe: from the left end */
            WXGShapeSample a=WXGRim26Field(-bar.width*.5+xe,y,bar,32),t=WXGCapsuleOpticalField((float)(-165+xe),(float)y,330,64);
            double e=fabs(a.distance-t.distance);if(e>worst)worst=e;
        }
        /* FIX123's canvas was 68 x 64: nearly round, so its ends were a circle's; at the join
           (6 degrees round the end) that is about 1.2 % of the radius off the real outline. */
        double jx=32-32*sin(6*M_PI/180),jy=-32*cos(6*M_PI/180);   /* from the left end, from the middle line */
        WXGShapeSample small=WXGCapsuleOpticalField((float)(-34+jx),(float)jy,68,64),real=WXGRim26Field(-bar.width*.5+jx,jy,bar,32);
        CHECK(worst<1e-4 && fabs(real.distance-small.distance)>.25,"the canvas' field is the real capsule's (worst %.5f); a 68 pt canvas' own was %.2f pt off at the join",worst,fabs(real.distance-small.distance));
    }
    /* FIX125: the rim as Core Animation borders from the outline, one pixel wider each: what
       each one-pixel ring shows under them is the profile's mean over that pixel. */
    {
        WXGRim26Bands l=WXGRim26BandsFor(0,s,3),g=WXGRim26BandsFor(1,s,3);
        CHECK(l.count==3 && fabs(l.width[0]-1./3)<1e-9 && fabs(l.width[2]-1)<1e-9,"1 pt at 3x: three bands, 1 / 2 / 3 pixels wide");
        CHECK(fabs(WXGRim26BandsShown(l,0)-.8833)<2e-3 && fabs(WXGRim26BandsShown(l,1)-.65)<2e-3 && fabs(WXGRim26BandsShown(l,2)-.4167)<2e-3,
              "rings show .883 .650 .417 (%.3f %.3f %.3f)",WXGRim26BandsShown(l,0),WXGRim26BandsShown(l,1),WXGRim26BandsShown(l,2));
        CHECK(fabs(l.alpha[2]-.4167)<2e-3 && fabs(l.alpha[1]-.4)<3e-3 && fabs(l.alpha[0]-.6667)<4e-3,"band opacities %.3f %.3f %.3f",l.alpha[0],l.alpha[1],l.alpha[2]);
        CHECK(fabs(WXGRim26BandsShown(g,0)-.04)<1e-3 && fabs(WXGRim26BandsShown(g,1)-.02)<1e-3 && WXGRim26BandsShown(g,2)<1e-6,"the faint line: full, half, none");
        /* the two sets, the lights' under the level along the outline, one over the other: WXGRim26Alpha */
        double worst=0;
        for(int a=0;a<360;a+=15)for(int m=0;m<3;m++) {
            double nx=cos(a*M_PI/180),ny=sin(a*M_PI/180),level=WXGRim26Along(nx,ny,s);
            double shown=1-(1-level*WXGRim26BandsShown(l,m))*(1-WXGRim26BandsShown(g,m)),want=0;
            for(int i=0;i<64;i++)want+=WXGRim26Alpha((m+(i+.5)/64)/3.,nx,ny,s)/64;
            if(fabs(shown-want)>worst)worst=fabs(shown-want);
        }
        CHECK(worst<.004,"bands under the level + the faint line = the formula, per pixel ring (worst %.4f)",worst);
        /* other heights and scales: the pixel rings, the last one its share; never rising inward; capped */
        WXGRim26Shape t=s;t.height=1.5;
        WXGRim26Bands h=WXGRim26BandsFor(0,t,2);   /* 3 px at 2x */
        CHECK(h.count==3 && fabs(h.width[2]-1.5)<1e-9,"1.5 pt at 2x: three bands");
        t.height=1.2;h=WXGRim26BandsFor(0,t,3);    /* 3.6 px: four rings, the last 60 % of a pixel */
        CHECK(h.count==4 && fabs(WXGRim26BandsShown(h,3)-.6*(1-.7*(1.1/1.2)))<.01,"1.2 pt at 3x: the 4th ring its share (%.3f)",WXGRim26BandsShown(h,3));
        t.height=4;h=WXGRim26BandsFor(0,t,3);
        int falling=1;for(int m=0;m+1<h.count;m++)if(WXGRim26BandsShown(h,m)<WXGRim26BandsShown(h,m+1)-1e-9)falling=0;
        CHECK(h.count==12 && falling,"4 pt at 3x: twelve bands, never rising inward");
        t.height=4;h=WXGRim26BandsFor(0,t,8);
        CHECK(h.count==WXG_RIM26_MAX_BANDS && fabs(h.width[h.count-1]-4)<1e-9,"more than the bands hold: wider rings to the same depth");
        t=s;t.curve=0;h=WXGRim26BandsFor(0,t,3);
        CHECK(fabs(h.alpha[2]-1)<1e-9 && h.alpha[0]==0 && h.alpha[1]==0,"no fall across: one full band 1 pt wide");
    }
    /* The optional shadow: exponential, the same all round. */
    CHECK(fabs(WXGRim26Shadow(0,s)-1)<1e-12 && fabs(WXGRim26Shadow(2.5,s)-exp(-1))<1e-12 && WXGRim26Shadow(-.1,s)==0,"shadow: exponential from the outline");
    unsigned char *ps=calloc((size_t)b.columns*b.rows,1);
    WXGRim26Fill(ps,b.columns,b,22,3,WXGRim26PartShadow,s,0);
    int st=ps[3*b.columns+66],sr=ps[66*b.columns+(b.columns-1-3)];   /* the same depth from the top and from the right */
    CHECK(abs(st-sr)<=2 && st>120 && st<200,"shadow even all round (%d %d)",st,sr);
    free(ps);

    if(failures){printf("Rim26Tests: %d failure(s)\n",failures);return 1;}
    printf("PASS: iOS 26 rim (FIX123, the system's recipe): 1 -> .30 over 1 pt then cut; |cos| about lower right / upper left; ring where the lights are out; dark matrix = the dumped one; dark button over slate and the light grey button all round match the captures; canvases; pixels within the 1 pt band, 3 px at 3x; bleed past the outline for the clipped layer; stretched columns alike; the real capsule's ends on the canvas (FIX124); the rim as borders one pixel wider each = the formula per pixel ring (FIX125); shadow.\n");
    return 0;
}
