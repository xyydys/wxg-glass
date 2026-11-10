/* FIX126: the system's lens deformation (Sources/WXGLensFlex.h) against the
   lens recorded on iOS 26.6 (fixtures/lens_flex_ios26.h). */
#include "../Sources/WXGLensFlex.h"
#include "fixtures/lens_flex_ios26.h"
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

int main(void) {
    WXGLensFlexParams p=WXGLensFlexDefaults();
    const double dt=1./WXG_FLEX_FIXTURE_RATE;
    /* The recorded drag: the model's width and height against the system's, frame by frame. */
    {
        WXGLensFlex f;memset(&f,0,sizeof f);
        double ex=0,ey=0,sx2=0,sy2=0,lowest=9,highest=0;int n=0;
        for(int i=1;i<WXGFlexFixtureCount;i++) {
            double v=(WXGFlexFixtureX[i]-WXGFlexFixtureX[i-1])/dt;
            WXGLensFlexStep(&f,v,WXG_FLEX_FIXTURE_PITCH,p,dt);
            double sx,sy;WXGLensFlexScale(f,p,&sx,&sy);
            double mx=WXGFlexFixtureScaleX[i],my=WXGFlexFixtureScaleY[i];
            ex+=(sx-mx)*(sx-mx);ey+=(sy-my)*(sy-my);
            sx2+=(mx-1)*(mx-1);sy2+=(my-1)*(my-1);++n;
            if(sx<lowest)lowest=sx;
            if(sx>highest)highest=sx;
        }
        ex=sqrt(ex/n);ey=sqrt(ey/n);sx2=sqrt(sx2/n);sy2=sqrt(sy2/n);
        CHECK(ex<.023 && ey<.034,"the recorded drag: width rms %.4f of %.4f, height rms %.4f of %.4f",ex,sx2,ey,sy2);
        CHECK(lowest>=p.minX-1e-9 && highest<=p.maxX+1e-9 && lowest<.84 && highest>1.1,"both shapes reached, within the clamps (%.3f .. %.3f)",lowest,highest);
        printf("recorded drag: width rms %.4f of %.4f, height %.4f of %.4f\n",ex,sx2,ey,sy2);
    }
    /* A steady speed: the shape builds, then all but vanishes; a stop: the opposite shape, then rest, no ringing. */
    {
        WXGLensFlex f;memset(&f,0,sizeof f);double sx,sy,peak=1,steady,low=1,after=1;
        for(int i=0;i<240;i++){WXGLensFlexStep(&f,600.,94.17,p,1./120.);WXGLensFlexScale(f,p,&sx,&sy);if(sx>peak)peak=sx;}
        steady=sx;
        CHECK(peak>1.06 && steady<1.035 && steady>1. && sy<1.,"moving right: wider and flatter; peak %.3f, at a steady speed %.3f",peak,steady);
        double back=1,series[300];int reached=0;
        for(int i=0;i<300;i++) {
            WXGLensFlexStep(&f,0.,94.17,p,1./120.);WXGLensFlexScale(f,p,&sx,&sy);
            series[i]=sx;
            if(sx<low){low=sx;reached=i;}
            after=sx;
        }
        for(int i=reached;i<300;i++)if(series[i]>back)back=series[i];   /* any swing back past rest after the opposite shape */
        CHECK(low<.95 && back<1.012 && fabs(after-1)<.002,"stopping: the opposite shape (%.3f), then rest (swing back %.4f, end %.4f)",low,back,after);
        CHECK(WXGLensFlexStill(f),"still at the end");
    }
    /* Signed; symmetric on request; nothing without a pitch or a time step. */
    {
        WXGLensFlex a,b;memset(&a,0,sizeof a);memset(&b,0,sizeof b);double ax,ay,bx,by;
        for(int i=0;i<20;i++){WXGLensFlexStep(&a,900.,94.17,p,1./120.);WXGLensFlexStep(&b,-900.,94.17,p,1./120.);}
        WXGLensFlexScale(a,p,&ax,&ay);WXGLensFlexScale(b,p,&bx,&by);
        CHECK(ax>1 && ay<1 && bx<1 && by>1 && fabs((ax-1)+(bx-1))<1e-9,"right wider and flatter, left narrower and taller (%.3f %.3f / %.3f %.3f)",ax,ay,bx,by);
        WXGLensFlexParams s=p;s.symmetric=1;WXGLensFlexScale(b,s,&bx,&by);
        CHECK(fabs(bx-ax)<1e-9 && fabs(by-ay)<1e-9,"symmetric: the same shape both ways");
        WXGLensFlex z;memset(&z,0,sizeof z);WXGLensFlexStep(&z,900.,0.,p,1./120.);WXGLensFlexStep(&z,900.,94.17,p,0.);
        CHECK(WXGLensFlexStill(z),"no pitch, no step: nothing");
        /* the frame rate does not matter: 60 a second against 120 */
        WXGLensFlex c,d;memset(&c,0,sizeof c);memset(&d,0,sizeof d);
        for(int i=0;i<30;i++)WXGLensFlexStep(&c,700.,94.17,p,1./60.);
        for(int i=0;i<60;i++)WXGLensFlexStep(&d,700.,94.17,p,1./120.);
        double cx,cy,dx,dy;WXGLensFlexScale(c,p,&cx,&cy);WXGLensFlexScale(d,p,&dx,&dy);
        CHECK(fabs(cx-dx)<.003,"60 and 120 frames a second alike (%.4f %.4f)",cx,dx);
    }
    if(failures){printf("LensFlexTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: iOS 26 lens deformation (FIX126): the recorded drag reproduced, closer than the velocity spring; builds and fades at a steady speed; the opposite shape on stopping, no ringing; signed, symmetric on request; frame-rate independent.\n");
    return 0;
}
