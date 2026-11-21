/* FIX88: the bar inside the dock's lens joins the bar outside at 45 degrees
   (WXGInnerInsetAlong / WXGLensDepthAlongBar), and the lens's colour split has
   its own band (WXGMeshOptics.dispersionWidth / dispersionTopRatio). */
#include "../Sources/WXGMeshRefraction.h"
#include <stdio.h>
static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)
/* The contour of the bar seen through the lens (no refraction): the top edge
   y(x) where barDistance + inset = 0, found by bisection. Bar 359 x 68 and a
   103 x 87 lens, both centred at the origin. */
static float insetAt(float x,float y) {
    WXGShapeSample b=WXGCapsuleOpticalField(x,y,359,68);
    float qx=x-b.nx*b.distance,qy=y-b.ny*b.distance;
    WXGShapeSample l=WXGCapsuleOpticalField(qx,qy,103,87);
    return WXGInnerInsetAlong(68,1,.18f,WXGLensDepthAlongBar(l.distance,-b.ny,b.nx,l.nx,l.ny));
}
static float contourY(float x) {
    float lo=-34.f,hi=0.f;   /* covered below, uncovered above */
    for(int i=0;i<60;i++){float m=(lo+hi)*.5f;float d=WXGCapsuleOpticalField(x,m,359,68).distance+insetAt(x,m);if(d<0)hi=m;else lo=m;}
    return hi;
}
int main(void) {
    float full=68*.5f*.18f;
    CHECK(WXGInnerInsetAlong(68,1,.18f,0)==0,"0 at the join");
    CHECK(fabsf(WXGInnerInsetAlong(68,1,.18f,.01f)/.01f-1)<.01f,"45 degrees at the join");
    CHECK(fabsf(WXGInnerInsetAlong(68,1,.18f,2*full)-full)<1e-5f && fabsf(WXGInnerInsetAlong(68,1,.18f,100)-full)<1e-5f,"full inset");
    for(float a=0;a<30;a+=.1f)CHECK(WXGInnerInsetAlong(68,1,.18f,a)<=WXGInnerInsetAlong(68,1,.18f,a+.1f)+1e-6f,"monotonic (%.1f)",a);
    CHECK(WXGInnerInsetAlong(68,0,.18f,10)==0 && WXGInnerInsetAlong(68,1,0,10)==0,"no press / no reduction: none");
    CHECK(fabsf(WXGInnerInsetAlong(68,1,.9f,100)-68*.5f*.3f)<1e-4f,"reduction clamped to .3");
    CHECK(WXGLensDepthAlongBar(2,1,0,1,0)==0 && fabsf(WXGLensDepthAlongBar(-3,1,0,.6f,.8f)-5)<1e-5f && fabsf(WXGLensDepthAlongBar(-3,1,0,0,1)-10)<1e-5f,
          "depth along the outline: outside 0, over |t.n|, at least .3");
    /* The contour along the top edge: at the lens edge on the bar's top line,
       never steeper than 45 degrees (+5%), reaching the full inset inside. */
    float join=-(51.5f-43.5f)-sqrtf(43.5f*43.5f-34.f*34.f);   /* the lens outline on y = -34, left side */
    float prev=contourY(join-1);
    CHECK(fabsf(prev+34)<.05f,"outside the lens: the bar's edge (%.3f)",prev);
    float steepest=0;
    for(float x=join-1+.25f;x<0;x+=.25f){float y=contourY(x);float s=fabsf(y-prev)/.25f;if(s>steepest)steepest=s;prev=y;}
    CHECK(steepest<1.05f,"no step steeper than 45 degrees (%.3f)",steepest);
    CHECK(fabsf(contourY(0)-(-34+full))<.05f,"full inset in the middle (%.3f)",contourY(0));
    /* Colour split band: zero fields are exactly the refraction band. */
    WXGMeshOptics o={.width=103,.height=87,.fieldScale=1,.edgeWidth=10,.refraction=1.15f,.offsetScale=1,.zoomBefore=1,.zoomAfter=1.2f,.dispersion=1.5f,.channel=1,.topRatio=.4f,.sharpness=3,.barLeft=-128,.barTop=9.5f,.barRight=231,.barBottom=77.5f};
    WXGMeshOptics same=o;same.dispersionWidth=10;same.dispersionTopRatio=.4f;
    WXGMeshOptics wide=o;wide.dispersionWidth=24;
    for(float y=1;y<43;y+=2.5f)for(float x=1;x<102;x+=3.5f) {
        float ax,ay,bx,by;WXGMeshSource(o,x,y,&ax,&ay);WXGMeshSource(same,x,y,&bx,&by);
        if(fabsf(ax-bx)>1e-4f || fabsf(ay-by)>1e-4f){CHECK(0,"same band, same mapping (%.1f, %.1f)",x,y);x=999;y=999;}
    }
    /* 15 pt in from the left end on the centre line: past the refraction band,
       inside the wider colour split. */
    float rx,ry,gx,gy;WXGMeshSource(o,15,43.5f,&rx,&ry);WXGMeshSource(wide,15,43.5f,&gx,&gy);
    WXGMeshOptics green=wide;green.channel=0;float zx,zy;WXGMeshSource(green,15,43.5f,&zx,&zy);
    CHECK(fabsf(gx-zx)>.05f,"wider colour split reaches further in (%.4f)",gx-zx);
    WXGMeshOptics green0=o;green0.channel=0;float z0x,z0y;WXGMeshSource(green0,15,43.5f,&z0x,&z0y);
    CHECK(fabsf(rx-z0x)<1e-5f,"refraction band only: no split there");
    /* FIX113 H: a margin around the shape changes nothing but where the
       shape sits in the layer; outward (negative scale) samples past the rim
       by the same amount inward samples in from it. */
    {
        const float PAD=20;
        WXGMeshOptics plain={.width=140,.height=72,.fieldScale=1,.edgeWidth=8,.refraction=6,.offsetScale=1,.zoomBefore=1,.zoomAfter=1.06f,.topRatio=.68f,.sharpness=4};
        WXGMeshOptics flat=plain;flat.zoomAfter=1;flat.width+=2*PAD;flat.height+=2*PAD;flat.padX=flat.padY=PAD;   /* (no zoom: the rim alone) */
        WXGMeshOptics padded=plain;padded.width+=2*PAD;padded.height+=2*PAD;padded.padX=padded.padY=PAD;
        for(float y=1;y<71;y+=3.5f)for(float x=1;x<139;x+=4.5f) {
            float ax,ay,bx,by;WXGMeshSource(plain,x,y,&ax,&ay);WXGMeshSource(padded,x+PAD,y+PAD,&bx,&by);
            if(fabsf(ax+PAD-bx)>1e-3f || fabsf(ay+PAD-by)>1e-3f){CHECK(0,"margin: same mapping, moved (%.1f, %.1f)",x,y);x=999;y=999;}
        }
        WXGMeshOptics flatOut=flat;flatOut.offsetScale=-1;
        float ix,iy,ox,oy;WXGMeshSource(flat,PAD+.5f,PAD+36,&ix,&iy);WXGMeshSource(flatOut,PAD+.5f,PAD+36,&ox,&oy);
        float in=ix-(PAD+.5f),out=(PAD+.5f)-ox;   /* left end, centre line: inward = +x */
        CHECK(in>1 && fabsf(in-out)<.01f && ox<PAD,"outward mirrors inward at the rim (in %.3f, out %.3f, from x %.3f)",in,out,ox);
        WXGMeshOptics outward=padded;outward.offsetScale=-1;
        static WXGMeshPoint P[20000];static unsigned int F[20000][4];int faces=0;
        int n=WXGBuildContourMesh(outward,(WXGMeshQuality){.20f,.16f,24.f},P,20000,F,20000,&faces);
        float minTo=1,maxTo=0,minFrom=1;
        for(int k=0;k<n;k++){minTo=fminf(minTo,P[k].toX);maxTo=fmaxf(maxTo,P[k].toX);minFrom=fminf(minFrom,P[k].fromX);}
        CHECK(n>0 && faces>0 && minTo>.005f && maxTo<.995f && minFrom<minTo-.02f,
              "padded contour mesh covers the shape (to %.3f..%.3f), samples into the margin (from %.3f)",minTo,maxTo,minFrom);
    }
    /* FIX113 I: the rim offset cancelled. 0 is the old curve exactly; 1 has
       no offset at the rim or the band's inner edge, pushes in between, never
       folds (slope >= 0.2) and stays within 0.29 band widths, at any strength. */
    {
        int same=1;
        for(float s=0;s<=20;s+=2.5f)for(float d=-25;d<=2;d+=.37f)
            if(WXGLensRefractionOffset(d,8,s,0)!=WXGOpticalOffset(d,8,s))same=0;
        CHECK(same,"cancel 0 is WXGOpticalOffset");
        for(float s=1;s<=20;s+=19) for(float w=8;w<=30;w+=22) {
            float worstSlope=9,most=0,prev=0;int first=1;
            for(float x=0;x<=w+2;x+=.01f) {
                float off=WXGLensRefractionOffset(-x,w,s,1),src=x+off;
                if(!first){float slope=(src-prev)/.01f;if(slope<worstSlope)worstSlope=slope;}
                prev=src;first=0;if(off>most)most=off;
            }
            CHECK(fabsf(WXGLensRefractionOffset(0,w,s,1))<1e-5f && fabsf(WXGLensRefractionOffset(-w,w,s,1))<1e-5f,"cancel 1: nothing at the rim or the band's edge (s %.0f, w %.0f)",s,w);
            CHECK(worstSlope>.19f && most<=.29f*w && (s<2 || most>.05f*w),"cancel 1: monotonic, near (s %.0f, w %.0f: slope %.3f, most %.3f)",s,w,worstSlope,most);
        }
        WXGMeshOptics mesh={.width=140,.height=72,.fieldScale=1,.edgeWidth=8,.refraction=20,.offsetScale=1,.zoomBefore=1,.zoomAfter=1,.topRatio=.68f,.sharpness=4,.cancel=1};
        float sx,sy;WXGMeshSource(mesh,.25f,36,&sx,&sy);
        CHECK(fabsf(sx-.25f)<.5f,"mesh: cancelled rim shows what is under it (%.3f)",sx);
    }
    /* FIX113 U: the lens shows the bar it captured made smaller. With no
       refraction, a 1.2 zoom and the bar centred on the lens: on the lens'
       middle column the bar's real top edge shows exactly the shader's inset
       (full) below where it lies; the middle line is the zoom's alone; the
       mapping down the column is continuous and never folds; the far ends
       change nothing there; shrink off is the old mapping exactly. */
    {
        WXGMeshOptics z={.width=103,.height=87,.fieldScale=1,.edgeWidth=10,.offsetScale=1,.zoomBefore=1,.zoomAfter=1.2f,.sbLeft=-10000,.sbTop=9.5f,.sbRight=10000,.sbBottom=77.5f,.shrinkPress=1,.shrinkPinch=.18f};
        WXGMeshOptics off=z;off.shrinkPress=0;
        float lo=0,hi=43.5f;   /* the display row whose source is the bar's top edge (9.5) */
        for(int i=0;i<60;i++){float m=(lo+hi)*.5f,sx,sy;WXGMeshSource(z,51.5f,m,&sx,&sy);if(sy<9.5f)lo=m;else hi=m;}
        float full=68*.5f*.18f;
        CHECK(fabsf(hi-(9.5f+full))<.05f,"the smaller bar's top edge shows the inset (%.3f, want %.3f)",hi,9.5f+full);
        float cx,cy,ux,uy;WXGMeshSource(z,51.5f,43.5f,&cx,&cy);WXGMeshSource(off,51.5f,43.5f,&ux,&uy);
        CHECK(fabsf(cx-ux)<1e-4f && fabsf(cy-uy)<1e-4f,"middle line: the zoom alone");
        float prev=-1e9f,worst=9,jump=0;
        for(float y=0;y<=87;y+=.05f){float sx,sy;WXGMeshSource(z,51.5f,y,&sx,&sy);if(prev>-1e8f){float sl=(sy-prev)/.05f;if(sl<worst)worst=sl;if(fabsf(sy-prev)>jump)jump=fabsf(sy-prev);}prev=sy;}
        CHECK(worst>.3f && jump<.2f,"continuous, never folds (slope %.3f, step %.3f)",worst,jump);
        int same=1;
        for(float y=1;y<86;y+=2.5f)for(float x=1;x<102;x+=3.5f){float ax,ay,bx,by;WXGMeshOptics plain0=z;plain0.sbLeft=plain0.sbTop=plain0.sbRight=plain0.sbBottom=0;
            WXGMeshSource(off,x,y,&ax,&ay);WXGMeshSource(plain0,x,y,&bx,&by);if(fabsf(ax-bx)>1e-5f || fabsf(ay-by)>1e-5f)same=0;}
        CHECK(same,"shrink off: the old mapping exactly");
        /* Where the bar's top edge meets the lens' outline (x 16.37) the inset
           is 0: the bar's edge shows where it lies, joining the bar outside. */
        lo=0;hi=43.5f;
        for(int i=0;i<60;i++){float m=(lo+hi)*.5f,sx,sy;WXGMeshSource(z,16.6f,m,&sx,&sy);if(sy<9.5f)lo=m;else hi=m;}
        CHECK(fabsf(hi-9.5f)<.5f,"at the lens' outline the bar's edge stays put (%.3f)",hi);
        /* FIX113 Y: an extra inset of 3 pt shows the edge 3 pt further in on the middle column. */
        WXGMeshOptics more=z;more.shrinkExtra=3;lo=0;hi=43.5f;
        for(int i=0;i<60;i++){float m=(lo+hi)*.5f,sx,sy;WXGMeshSource(more,51.5f,m,&sx,&sy);if(sy<9.5f)lo=m;else hi=m;}
        CHECK(fabsf(hi-(9.5f+full+3))<.05f,"the extra inset adds to it (%.3f, want %.3f)",hi,9.5f+full+3);
        /* FIX113 Y (review): the lens squashed 13 pt (extra 6.5) and 20 pt (67
           pt, shorter than the 68 pt bar: its outline lies outside the lens),
           and swollen 13 / 30 pt (extra -6.5 / -15; at 30 the smaller bar
           comes out past the real one): the smaller bar's edge stays as far
           from the rim as at rest. */
        float rest=9.5f+full,amounts[4]={-13,-20,13,30};
        for(int k=0;k<4;k++) {
            float a=amounts[k];
            WXGMeshOptics q=z;q.height=87.f+a;q.sbTop=9.5f+a*.5f;q.sbBottom=77.5f+a*.5f;q.shrinkExtra=-a*.5f;
            lo=0;hi=q.height*.5f;
            for(int i=0;i<60;i++){float m=(lo+hi)*.5f,sx,sy;WXGMeshSource(q,51.5f,m,&sx,&sy);if(sy<q.sbTop)lo=m;else hi=m;}
            CHECK(fabsf(hi-rest)<.1f,"lens %+.0f pt: the strip holds (%.3f, at rest %.3f)",a,hi,rest);
        }
    }
    if(failures){printf("LensInsetAlongTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: lens inset along the bar (FIX88): 45 degrees at the join, flattening to the full inset, never a vertical step on the lens' side; the colour split's own band (unchanged when equal, reaching further when wider); FIX113 H: a margin only moves the mapping, outward mirrors inward at the rim and samples into the margin; FIX113 I: the rim offset cancelled (0 unchanged, 1 nothing at the rim, never folds, stays near); FIX113 U: the smaller bar (its edge at the inset, middle line unchanged, continuous, off = old mapping); FIX113 Y: the extra inset, the strip held squashed / shorter than the bar / swollen.\n");
    return 0;
}
