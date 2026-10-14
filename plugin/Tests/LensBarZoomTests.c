/* FIX94: the bar seen through the lens follows the lens' rim
   (Sources/WXGLensOptics.h WXGLensBarZoom, Sources/WXGTravelVeil.h). */
#include "../Sources/WXGTravelVeil.h"
#include <stdio.h>
static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)
int main(void) {
    /* The tester's dock: bar 321 x 63.25 (pressed), lens 97.3 x 74.73 on a
       middle tab, band 19.18 at the ends, 1/3 above and below, sharpness 3.25,
       inset 0.131, margin 0.5. */
    const float bw=321,bh=63.25f,lw=97.3f,lh=74.73f,side=19.18f,ratio=.3327f,sharp=3.254f,pinch=.131f,m=.5f;
    float top=side*ratio,lhalf=lh*.5f;
    CHECK(WXGLensBarZoom(0,0,0,bw,bh,0,0,lw,lh,bh,1,pinch,side,ratio,sharp,0)==1.f,"margin 0: off");
    CHECK(WXGLensBarZoom(300,0,0,bw,bh,0,0,lw,lh,bh,1,pinch,side,ratio,sharp,m)==1.f,"outside the lens: 1");
    /* The middle column: the inset top edge lands margin x the band from the rim. */
    float full=bh*.5f*pinch,z=WXGLensBarZoom(0,0,0,bw,bh,0,0,lw,lh,bh,1,pinch,side,ratio,sharp,m);
    float edge=(bh*.5f-full)*z;
    CHECK(z>1.05f && fabsf(edge-(lhalf-m*top))<.05f,"middle: edge %.3f from the centre, wanted %.3f (z %.4f)",edge,lhalf-m*top,z);
    /* Toward the lens' end the scale falls smoothly to 1 (the 45-degree join stays). */
    float previous=z;int monotonic=1;
    for(float x=0;x<lw*.5f;x+=.25f){float k=WXGLensBarZoom(x,0,0,bw,bh,0,0,lw,lh,bh,1,pinch,side,ratio,sharp,m);if(k>previous+1e-4f)monotonic=0;previous=k;}
    CHECK(monotonic,"never grows toward the lens' end");
    CHECK(WXGLensBarZoom(lw*.5f-.5f,0,0,bw,bh,0,0,lw,lh,bh,1,pinch,side,ratio,sharp,m)<1.02f,"at the lens' end about 1");
    /* No press: no inset, still at least 1 and finite. */
    float z0=WXGLensBarZoom(0,0,0,bw,bh,0,0,lw,lh,bh,0,pinch,side,ratio,sharp,m);
    CHECK(z0>=1.f && z0<2.f,"unpressed %.4f",z0);
    /* A bar end cap inside the lens takes its straight part's scale. */
    float lx=bw*.5f-lw*.5f+6,straightEnd=bw*.5f-bh*.5f;
    float atEnd=WXGLensBarZoom(straightEnd,0,0,bw,bh,lx,0,lw,lh,bh,1,pinch,side,ratio,sharp,m);
    CHECK(fabsf(WXGLensBarZoom(straightEnd+10,0,0,bw,bh,lx,0,lw,lh,bh,1,pinch,side,ratio,sharp,m)-atEnd)<1e-6f,"cap: the straight end's scale");
    /* The lens' end over the bar's end cap (dragging onto / off an end tab):
       wherever the bar is magnified, its outline stays inside the lens' rim,
       and the scale changes smoothly from column to column (where there is
       bar: the last 2 pt of the cap's tip are a sliver, past it none). */
    {
        enum {M=181};float cap[4*M];WXGLensFollow f={side,ratio,sharp,m};
        int inside=1,smooth=1;float worst=-1e9f,jump=0;
        for(float shift=-14;shift<=8.01f;shift+=2) {
            float cx=bw*.5f-lw*.5f+shift;
            WXGTravelVeilOutline(0,0,bw,bh,cx,0,lw,lh,bh,1,pinch,0,cx-lw*.5f-2,cx+lw*.5f+2,M,cap,&f);
            for(int i=0;i<2*M;i++) {
                float px=cap[2*i],py=cap[2*i+1];
                float k=WXGLensBarZoom(px,0,0,bw,bh,cx,0,lw,lh,bh,1,pinch,side,ratio,sharp,m);
                if(k<1.01f)continue;
                float d=WXGCapsuleOpticalField(px-cx,py,lw,lh).distance;
                if(d>worst)worst=d;
                if(d>0.f)inside=0;
            }
            float prev=WXGLensBarZoom(cx-lw*.5f,0,0,bw,bh,cx,0,lw,lh,bh,1,pinch,side,ratio,sharp,m);
            for(float x=cx-lw*.5f;x<=WXG_MIN(cx+lw*.5f,bw*.5f-2);x+=.25f) {
                float k=WXGLensBarZoom(x,0,0,bw,bh,cx,0,lw,lh,bh,1,pinch,side,ratio,sharp,m);
                if(fabsf(k-prev)>jump)jump=fabsf(k-prev);
                prev=k;
            }
        }
        if(jump>.03f)smooth=0;
        CHECK(inside,"cap under the lens' end: magnified outline %.3f pt past the rim",worst);
        CHECK(smooth,"cap under the lens' end: scale jumps %.4f between 0.25 pt columns",jump);
    }
    /* The tap animation's veil follows: the top point in the middle column is
       margin x band below the lens' top rim; outside the lens unchanged. */
    enum {N=97};float pts[4*N],plain[4*N];
    WXGLensFollow follow={side,ratio,sharp,m};
    WXGTravelVeilOutline(0,0,bw,bh,0,0,lw,lh,bh,1,pinch,0,-lw*.5f-2,lw*.5f+2,N,pts,&follow);
    WXGTravelVeilOutline(0,0,bw,bh,0,0,lw,lh,bh,1,pinch,0,-lw*.5f-2,lw*.5f+2,N,plain,NULL);
    float mid=pts[2*(N/2)+1];
    CHECK(fabsf(mid-(-lhalf+m*top))<.06f,"veil top at %.3f, wanted %.3f",mid,-lhalf+m*top);
    CHECK(fabsf(pts[1]-plain[1])<1e-4f && fabsf(pts[2*(N-1)+1]-plain[2*(N-1)+1])<1e-4f,"outside the lens: the outline itself");
    for(int i=0;i<2*N;i++)CHECK(fabsf(pts[2*i])<=lw*.5f+2.01f && fabsf(pts[2*i+1])<lhalf+1e-3f,"inside the lens' height (%d)",i);
    if(failures){printf("LensBarZoomTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: bar following the lens' rim (FIX94): off at margin 0, the middle edge margin x band from the rim, falling to 1 toward the join, end cap at its straight end's scale and never past the rim under the lens' end, the tap animation's veil the same.\n");
    return 0;
}
