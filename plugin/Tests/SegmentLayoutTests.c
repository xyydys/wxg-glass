#include "../Sources/WXGSegmentLayout.h"
#include <assert.h>
#include <stdio.h>

static int near(float a,float b) {return fabsf(a-b)<.001f;}

static void checkTitlePair(float limit,float height,float gap,float shortTitle,float longTitle) {
    float widths[]={shortTitle,longTitle};
    float ideal=WXGTitlePreferredWidth(height,gap,widths);
    float width=fminf(limit,ceilf(ideal));
    WXGSegmentSlots s=WXGMakeSegmentSlots(width,gap,2,widths);
    float padding[2];
    for(int i=0;i<2;i++) {
        float cell=s.edges[i+1]-s.edges[i];
        padding[i]=(cell-widths[i]*s.fontScale)*.5f;
        assert(padding[i]>=0.f);
        assert(WXGSegmentAtX(s,WXGSegmentCenter(s,i))==i);
        WXGDockGeometry g=WXGSegmentGeometry(width,height,gap,WXGSegmentCenter(s,i),0,1.15f,1.03f,3,s);
        assert(near(g.lensX,s.edges[i]));
        assert(near(g.lensWidth,cell));
    }
    assert(near(padding[0],padding[1]));
    if(limit>=ideal) {
        assert(near(s.fontScale,1));
        assert(padding[0]>=fmaxf(10,height*.35f)-.001f);
    }
    assert(WXGSegmentAtX(s,s.edges[1]-.001f)==0);
    assert(WXGSegmentAtX(s,s.edges[1])==1);
    assert(WXGSegmentAtX(s,-1)==0 && WXGSegmentAtX(s,width+1)==1);
    for(int i=0;i<=100;i++) {
        float t=i*.01f;
        float x=WXGSegmentCenter(s,0)+t*(WXGSegmentCenter(s,1)-WXGSegmentCenter(s,0));
        WXGDockGeometry g=WXGSegmentGeometry(width,height,gap,x,0,1.15f,1.03f,3,s);
        assert(near(g.lensX+g.lensWidth*.5f,x));
        for(int p=0;p<=10;p++) {
            float press=p*.1f;
            WXGDockGeometry a=WXGSegmentGeometry(width,height,gap,WXGSegmentCenter(s,0),press,1.15f,1.03f,3,s);
            WXGDockGeometry b=WXGSegmentGeometry(width,height,gap,WXGSegmentCenter(s,1),press,1.15f,1.03f,3,s);
            WXGDockGeometry mid=WXGSegmentGeometry(width,height,gap,x,press,1.15f,1.03f,3,s);
            assert(near(mid.lensWidth,a.lensWidth+(b.lensWidth-a.lensWidth)*t));
            assert(near(mid.lensX,a.lensX+(b.lensX-a.lensX)*t));
        }
    }
}

int main(void) {
    assert(near(WXGSegmentGlideDuration(1),.252f));
    assert(near(WXGSegmentGlideDuration(-1),.252f));
    assert(near(WXGSegmentGlideDuration(2),.266f));
    assert(near(WXGSegmentGlideDuration(3),.28f));
    assert(near(WXGSegmentGlideDuration(5),.28f));
    // SF text-like advances for All/Unread, Chinese, reversed labels and an oversized name.
    const float titles[][2]={{16,47},{30,30},{68,16},{191,9}};
    for(int w=64;w<=320;w+=8)
        for(int h=28;h<=52;h+=4)
            for(size_t i=0;i<sizeof(titles)/sizeof(titles[0]);i++)
                checkTitlePair(w,h,WXGSelectionGap(5.25f,h),titles[i][0],titles[i][1]);

    // The search-replacement bar retains its equal cells, lens endpoints and hit boundaries.
    for(int n=1;n<=WXG_SEGMENTS_MAX;n++) {
        const float width=347.5f,gap=4.25f,height=42;
        WXGSegmentSlots s=WXGMakeSegmentSlots(width,gap,n,NULL);
        float step=(width-2*gap)/n;
        for(int i=0;i<n;i++) {
            float cx=gap+step*(i+.5f);
            assert(near(WXGSegmentCenter(s,i),cx));
            assert(WXGSegmentAtX(s,cx)==i);
            for(int p=0;p<=10;p++) {
                float press=p*.1f;
                WXGDockGeometry g=WXGSegmentGeometry(width,height,gap,cx,press,1.2f,1.05f,3,s);
                float lensWidth=WXGLensWidth(step,height,press,1.2f,0)*g.scale;
                float outside=gap*g.scale*(1-press)-3*press;
                float t=n>1?(float)i/(n-1):0;
                assert(near(g.lensWidth,lensWidth));
                assert(near(g.lensX,g.barX+outside+t*(g.barWidth-2*outside-lensWidth)));
            }
        }
    }
    puts("PASS: measured home title padding, constrained fitting, variable lens travel and hits; equal list segments");
    return 0;
}
