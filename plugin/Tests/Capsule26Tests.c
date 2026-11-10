/* FIX133: iOS 26's capsule outline (Sources/WXGCapsule26.h). */
#include "../Sources/WXGCapsule26.h"
#include <stdio.h>
static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)
enum { CAP=4*WXG_CAPSULE26_QUARTER_MAX };
/* The signed distance from a point to the plain stadium w x h (lying), < 0 inside. */
static double stadium(double x,double y,double w,double h) {
    double r=h*.5,cx=x<r?r:(x>w-r?w-r:x);
    return hypot(x-cx,y-r)-r;
}
int main(void) {
    /* The measured profile: nothing at and past its two ends, 1.36 % where the half circle would begin, at most
       1.70 % a tenth of a radius into the round end, half way down again 0.2 R before the end. */
    CHECK(WXGCapsule26Dip(.5)==0 && WXGCapsule26Dip(.8)==0 && WXGCapsule26Dip(-.55)==0 && WXGCapsule26Dip(-.9)==0,"nothing outside the stretch");
    CHECK(fabs(WXGCapsule26Dip(0)-.0136)<1e-9 && fabs(WXGCapsule26Dip(-.1)-.0170)<1e-9 && fabs(WXGCapsule26Dip(.2)-.0058)<1e-9,"the measured points");
    double deepest=0,at=0,worst=0,previous=0;
    for(double u=-.55;u<=.5;u+=.001) {
        double d=WXGCapsule26Dip(u);
        if(d>deepest){deepest=d;at=u;}
        if(fabs(d-previous)>worst)worst=fabs(d-previous);
        CHECK(d>=0,"never out of the stadium (%.3f)",u);
        previous=d;
    }
    CHECK(fabs(deepest-WXG_CAPSULE26_DEEPEST)<.0003 && at>-.14 && at<-.06,"deepest 1.70 %% just inside the round end (%.4f at %.3f)",deepest,at);
    CHECK(worst<.0001,"smooth (largest step %.6f per 0.001 R)",worst);
    for(double u=0;u<.5;u+=.01)CHECK(WXGCapsule26Dip(u+.01)<=WXGCapsule26Dip(u)+1e-9,"falling along the straight edge (%.2f)",u);

    /* The system's capsule, 120 x 44: every point inside the stadium, by at most 1.7 % of 22 pt; the tips and the
       middles of the long edges on it; symmetric; closed; no jump between neighbours; the long edge straight only
       over its middle (it has left its line 11 pt before the round end). */
    static double xs[CAP],ys[CAP];
    int n=WXGCapsule26Outline(120,44,xs,ys,CAP);
    CHECK(n>100 && n<=CAP,"points (%d)",n);
    double in=0,gap=0,left=1e9,right=-1e9,top=1e9,bottom=-1e9;
    for(int i=0;i<n;i++) {
        double d=stadium(xs[i],ys[i],120,44);
        CHECK(d<1e-6,"inside the stadium (%d: %.4f)",i,d);
        if(-d>in)in=-d;
        int j=(i+1)%n;double step=hypot(xs[j]-xs[i],ys[j]-ys[i]);
        if(step>gap && !(fabs(ys[i]-ys[j])<1e-9 && (ys[i]<1e-9 || ys[i]>44-1e-9)))gap=step;   /* but the straight middle */
        if(xs[i]<left)left=xs[i];
        if(xs[i]>right)right=xs[i];
        if(ys[i]<top)top=ys[i];
        if(ys[i]>bottom)bottom=ys[i];
    }
    CHECK(fabs(in-.0170*22)<.02,"at most 1.7 %% of the radius in (%.3f pt)",in);
    CHECK(gap<1.1,"no jump (largest step %.3f pt)",gap);
    CHECK(fabs(left)<1e-9 && fabs(right-120)<1e-9 && fabs(top)<1e-9 && fabs(bottom-44)<1e-9,"its box (%.3f %.3f %.3f %.3f)",left,right,top,bottom);
    int mirrored=1;
    for(int i=0;i<n;i++) {
        int found=0;
        for(int j=0;j<n;j++)if(fabs(xs[j]-(120-xs[i]))<1e-9 && fabs(ys[j]-(44-ys[i]))<1e-9)found=1;
        if(!found)mirrored=0;
    }
    CHECK(mirrored,"the same turned half round");
    double area=0;
    for(int i=0;i<n;i++){int j=(i+1)%n;area+=xs[i]*ys[j]-xs[j]*ys[i];}
    CHECK(area>0,"clockwise on a screen (y down)");
    double straightFrom=1e9;
    for(int i=0;i<n;i++)if(ys[i]<1e-9 && xs[i]<60 && xs[i]<straightFrom)straightFrom=xs[i];
    CHECK(fabs(straightFrom-(22+.5*22))<.01,"the top edge straight from 33 pt on (%.3f)",straightFrom);
    /* at the place the half circle would begin: 1.36 % of R under the line */
    double atJunction=-1;
    for(int i=0;i<n;i++)if(ys[i]<10 && fabs(xs[i]-22)<.25 && (atJunction<0 || fabs(xs[i]-22)<.05))atJunction=ys[i];
    CHECK(fabs(atJunction-.0136*22)<.03,"1.36 %% under the line where the round end begins (%.4f pt)",atJunction);

    /* A circle stays a circle; a short capsule has less of it; a long one all; a standing one is the lying one turned. */
    CHECK(WXGCapsule26Share(44,44)==0 && WXGCapsule26Share(120,44)==1 && fabs(WXGCapsule26Share(55,44)-.5)<1e-9 && WXGCapsule26Share(44,120)==1,"share");
    n=WXGCapsule26Outline(44,44,xs,ys,CAP);
    double off=0;
    for(int i=0;i<n;i++){double d=fabs(hypot(xs[i]-22,ys[i]-22)-22);if(d>off)off=d;}
    CHECK(n>20 && off<1e-9,"a circle (%.2e)",off);
    n=WXGCapsule26Outline(55,44,xs,ys,CAP);in=0;
    for(int i=0;i<n;i++){double d=-stadium(xs[i],ys[i],55,44);CHECK(d>-1e-6,"short: inside");if(d>in)in=d;}
    CHECK(fabs(in-.5*.0170*22)<.02,"a short capsule: half the dip (%.3f pt)",in);
    static double vx[CAP],vy[CAP];
    n=WXGCapsule26Outline(120,44,xs,ys,CAP);
    int m=WXGCapsule26Outline(44,120,vx,vy,CAP),turned=m==n;
    for(int i=0;i<m && turned;i++) {
        int found=0;
        for(int j=0;j<n;j++)if(fabs(vx[i]-(44-ys[j]))<1e-9 && fabs(vy[i]-xs[j])<1e-9)found=1;
        if(!found)turned=0;
    }
    CHECK(turned,"standing: the lying one turned");
    area=0;
    for(int i=0;i<m;i++){int j=(i+1)%m;area+=vx[i]*vy[j]-vx[j]*vy[i];}
    CHECK(area>0,"standing: clockwise too");
    /* little room: fewer points, still closed and inside */
    n=WXGCapsule26Outline(120,44,xs,ys,48);
    CHECK(n>=8 && n<=48,"fewer points (%d)",n);
    for(int i=0;i<n;i++)CHECK(stadium(xs[i],ys[i],120,44)<1e-6,"fewer points: inside");

    /* Which glass: capsules longer than high; not circles, not rounded rectangles, not slivers. */
    CHECK(WXGCapsule26Applies(120,44,22) && WXGCapsule26Applies(398,62,31) && WXGCapsule26Applies(73.3,41.3,20.65) && WXGCapsule26Applies(44,120,22),"capsules");
    CHECK(!WXGCapsule26Applies(44,44,22) && !WXGCapsule26Applies(140,90,24) && !WXGCapsule26Applies(120,44,12) && !WXGCapsule26Applies(45,44,22) && !WXGCapsule26Applies(20,3,1.5),"the rest as they were");

    if(failures){printf("Capsule26Tests: %d failure(s)\n",failures);return 1;}
    printf("PASS: iOS 26 capsule outline (FIX133): the measured dip (0 .. 1.70%% of the radius, from half a radius before the round end to 0.55 into it), inside the stadium, symmetric, clockwise, circles and short capsules, standing ones\n");
    return 0;
}
