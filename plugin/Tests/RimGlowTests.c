/* FIX86: the iOS 27-like rim (Sources/WXGRimGlow.h). */
#include "../Sources/WXGRimGlow.h"
#include <stdio.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

int main(void) {
    /* Along the outline (angle 0): 1 on the top / bottom, endLevel at the
       ends, monotonic, a larger sharpness dims sooner. */
    CHECK(WXGRimGlowLevel(0,1,0,.15,2)==1 && WXGRimGlowLevel(0,-1,0,.15,2)==1,"top and bottom full");
    CHECK(fabs(WXGRimGlowLevel(1,0,0,.15,2)-.15)<1e-12 && fabs(WXGRimGlowLevel(-1,0,0,.15,2)-.15)<1e-12,"ends at the end level");
    for(double k=.5;k<=6;k+=.5)for(double a=0;a<1;a+=.01)
        CHECK(WXGRimGlowLevel(sqrt(1-a*a),a,0,.15,k)<=WXGRimGlowLevel(sqrt(1-(a+.01)*(a+.01)),a+.01,0,.15,k)+1e-12,"monotonic toward the top (k %.1f)",k);
    double diagonal=sqrt(.5);
    CHECK(WXGRimGlowLevel(diagonal,diagonal,0,0,4)<WXGRimGlowLevel(diagonal,diagonal,0,0,2) && WXGRimGlowLevel(diagonal,diagonal,0,0,2)<WXGRimGlowLevel(diagonal,diagonal,0,0,1),"sharpness dims the corners sooner");
    CHECK(fabs(WXGRimGlowLevel(diagonal,diagonal,0,0,2)-.5)<1e-12,"45 degrees at sharpness 2 is half");
    CHECK(WXGRimGlowLevel(.6,.8,0,1,3)==1,"end level 1: even all round");
    CHECK(WXGRimGlowLevel(0,.5,0,-2,1)==.5 && WXGRimGlowLevel(0,.5,0,7,1)==1 && WXGRimGlowLevel(NAN,NAN,0,.2,1)==1,"clamped");
    /* FIX87: the highlight's direction. 90: the two ends full, top / bottom at
       the end level; 45: top-left and bottom-right full (y down), the other
       diagonal at the end level; 180 is 0 again; symmetric either way. */
    CHECK(fabs(WXGRimGlowLevel(1,0,90,.15,2)-1)<1e-12 && fabs(WXGRimGlowLevel(-1,0,90,.15,2)-1)<1e-12,"90: the ends full");
    CHECK(fabs(WXGRimGlowLevel(0,1,90,.15,2)-.15)<1e-12 && fabs(WXGRimGlowLevel(0,-1,90,.15,2)-.15)<1e-12,"90: top and bottom at the end level");
    CHECK(fabs(WXGRimGlowLevel(-diagonal,-diagonal,45,.1,2)-1)<1e-12 && fabs(WXGRimGlowLevel(diagonal,diagonal,45,.1,2)-1)<1e-12,"45: top-left and bottom-right full");
    CHECK(fabs(WXGRimGlowLevel(diagonal,-diagonal,45,.1,2)-.1)<1e-12,"45: top-right at the end level");
    CHECK(fabs(WXGRimGlowLevel(diagonal,-diagonal,135,.1,2)-1)<1e-12,"135: top-right full");
    for(double t=0;t<6.3;t+=.1)CHECK(fabs(WXGRimGlowLevel(cos(t),sin(t),0,.2,2)-WXGRimGlowLevel(cos(t),sin(t),180,.2,2))<1e-9 &&
                                      fabs(WXGRimGlowLevel(cos(t),sin(t),30,.2,2)-WXGRimGlowLevel(-cos(t),-sin(t),30,.2,2))<1e-12,"180 = 0, symmetric (%.1f)",t);
    CHECK(WXGRimGlowLevel(0,1,NAN,.15,2)==1,"a missing angle is 0");

    /* Across the edge: about 1 px steps; nested bands from the outline, each
       one step wider; composited, step j shows the curve at its middle,
       decreasing inward; at most the maximum. */
    double inset[WXG_RIM_GLOW_MAX_BANDS],width[WXG_RIM_GLOW_MAX_BANDS],alpha[WXG_RIM_GLOW_MAX_BANDS];
    int n=WXGRimGlowBands(2,1.6,3,WXG_RIM_GLOW_MAX_BANDS,inset,width,alpha);
    CHECK(n==6,"2 pt at 3x: 6 steps (%d)",n);
    for(int j=0;j<n;j++) {
        CHECK(inset[j]==0 && fabs(width[j]-(j+1)*2./6)<1e-12,"nested from the outline (%d)",j);
        CHECK(alpha[j]>=0 && alpha[j]<=1,"alpha in range (%d)",j);
        double depth=(j+.5)*2./6,shown=WXGRimGlowComposite(width,alpha,n,depth);
        CHECK(fabs(shown-pow(1-(j+.5)/6,1.6))<1e-9,"step %d shows the curve at its middle (%.4f)",j,shown);
        if(j)CHECK(shown<WXGRimGlowComposite(width,alpha,n,depth-2./6),"fading inward (%d)",j);
    }
    CHECK(fabs(width[n-1]-2)<1e-12 && WXGRimGlowComposite(width,alpha,n,2.01)==0,"covers the width, nothing past it");
    /* The total light hardly depends on the screen scale. */
    double total[2];
    for(int i=0;i<2;i++){double sc=i?2:3;int m=WXGRimGlowBands(2,1.6,sc,WXG_RIM_GLOW_MAX_BANDS,inset,width,alpha);total[i]=0;
        for(int j=0;j<m;j++)total[i]+=WXGRimGlowComposite(width,alpha,m,(j+.5)*2./m)*2./m;}
    CHECK(fabs(total[0]-total[1])<.02,"scale independent (%.3f %.3f)",total[0],total[1]);
    CHECK(WXGRimGlowBands(8,1,3,WXG_RIM_GLOW_MAX_BANDS,inset,width,alpha)==WXG_RIM_GLOW_MAX_BANDS,"capped");
    n=WXGRimGlowBands(.3,1,2,WXG_RIM_GLOW_MAX_BANDS,inset,width,alpha);
    CHECK(n==1 && fabs(alpha[0]-.5)<1e-12,"a thin glow is one step at its middle level");
    CHECK(WXGRimGlowBands(0,1,3,4,inset,width,alpha)==0 && WXGRimGlowBands(1,1,3,0,inset,width,alpha)==0 && WXGRimGlowBands(NAN,1,3,4,inset,width,alpha)==0,"nothing");
    n=WXGRimGlowBands(2,4,0,WXG_RIM_GLOW_MAX_BANDS,inset,width,alpha);
    CHECK(n==6 && WXGRimGlowComposite(width,alpha,n,1.9)<.001,"default scale 3, steep curve");
    n=WXGRimGlowBands(1,1,3,WXG_RIM_GLOW_MAX_BANDS,inset,width,alpha);
    CHECK(n==3,"whole pixels: 1 pt at 3x is 3 steps (%d)",n);

    /* FIX109 B: the 普通 line with a soft glow (WXGRimSoftBands): the line
       itself one band at full level, the glow's steps each at the curve's
       average, never brighter inward, the edge between line and glow kept,
       at most the maximum, the total light the line plus the glow's
       integral; then the opacity taken into the alphas. */
    double cases[][4]={{1,.8,.5,3},{.75,1.5,.35,3},{.5,.6,.7,2},{0,1,.6,3},{2,4,1,3},{1,0,.5,3},{.3,.1,.2,3}};
    for(size_t c=0;c<sizeof cases/sizeof *cases;c++) {
        double core=cases[c][0],soft=cases[c][1],level=cases[c][2],sc=cases[c][3];
        n=WXGRimSoftBands(core,soft,level,sc,WXG_RIM_GLOW_MAX_BANDS,inset,width,alpha);
        CHECK(n>=1 && n<=WXG_RIM_GLOW_MAX_BANDS,"soft %.2f/%.2f: count %d",core,soft,n);
        CHECK(fabs(width[n-1]-(core+soft))<1e-9 && WXGRimGlowComposite(width,alpha,n,core+soft+.01)==0,"soft %.2f/%.2f: covers line and glow only",core,soft);
        if(core>0 && level<.999)CHECK(fabs(WXGRimGlowComposite(width,alpha,n,core*.5)-1)<1e-9 && fabs(width[0]-core)<1e-9,"soft %.2f/%.2f: the line is solid and its own band",core,soft);
        double previous=2,sum=0,start=0;
        for(int j=0;j<n;j++) {
            CHECK(inset[j]==0 && width[j]>start && alpha[j]>=0 && alpha[j]<=1,"soft band %d",j);
            double shown=WXGRimGlowComposite(width,alpha,n,(start+width[j])*.5);
            double expect=((width[j]<core?width[j]:core)-(start<core?start:core))+(width[j]>core?WXGRimSoftIntegral(start>core?start:core,width[j],core,soft,level):0);
            CHECK(fabs(shown-expect/(width[j]-start))<1e-9,"soft %.2f/%.2f: step %d shows its average (%.4f %.4f)",core,soft,j,shown,expect/(width[j]-start));
            CHECK(shown<=previous+1e-12,"soft: not brighter inward (%d)",j);
            previous=shown;sum+=shown*(width[j]-start);start=width[j];
        }
        CHECK(fabs(sum-(core+WXGRimSoftIntegral(core,core+soft,core,soft,level)))<1e-9,"soft %.2f/%.2f: total light",core,soft);
    }
    n=WXGRimSoftBands(1,.8,.5,3,WXG_RIM_GLOW_MAX_BANDS,inset,width,alpha);
    CHECK(n>=8 && width[1]-width[0]<.1 && WXGRimGlowComposite(width,alpha,n,1.04)<.55 && WXGRimGlowComposite(width,alpha,n,1.04)>.4,"the glow starts at its level in quarter-pixel steps");
    CHECK(WXGRimGlowComposite(width,alpha,n,1.75)<.02,"and is nearly gone at its end");
    double before[WXG_RIM_GLOW_MAX_BANDS];
    for(int j=0;j<n;j++)before[j]=WXGRimGlowComposite(width,alpha,n,(j?width[j-1]:0)+(width[j]-(j?width[j-1]:0))*.5);
    WXGRimScaleBands(alpha,n,.6);
    for(int j=0;j<n;j++)CHECK(fabs(WXGRimGlowComposite(width,alpha,n,(j?width[j-1]:0)+(width[j]-(j?width[j-1]:0))*.5)-.6*before[j])<1e-9,"scaled step %d",j);
    CHECK(WXGRimSoftBands(0,0,.5,3,4,inset,width,alpha)==0 && WXGRimSoftBands(0,1,0,3,4,inset,width,alpha)==0 && WXGRimSoftBands(1,1,.5,3,0,inset,width,alpha)==0,"soft: nothing");
    CHECK(WXGRimSoftBands(1,0,.5,3,20,inset,width,alpha)==1 && alpha[0]==1,"no glow: the plain line");

    if(failures){printf("RimGlowTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: iOS 27-like rim (FIX86/87): along the outline full where it faces the highlight angle (0 top / bottom, 90 ends, diagonals), end level across it, monotonic, sharpness, symmetric; across the edge about 1 px steps as nested bands from the outline, composited to the curve at each step's middle, fading inward, scale independent, capped. FIX109 B soft line: the line solid, a Gaussian glow inside it in quarter-pixel steps, each its average, total light exact, opacity folded into the alphas.\n");
    return 0;
}
