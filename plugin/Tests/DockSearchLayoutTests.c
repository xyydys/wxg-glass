#include "../Sources/WXGDockSearchLayout.h"
#include "../Sources/WXGMotion.h"
#include <assert.h>
#include <stdio.h>

static int near(float a,float b) {return fabsf(a-b)<.01f;}
/* Left / right shape of a layout: the field ends left, the close button right. */
static float leftX(WXGDockSearchSpans s,int leading) {return leading?s.searchX:s.capsuleX;}
static float rightEnd(WXGDockSearchSpans s,int leading) {return leading?s.capsuleX+s.capsuleW:s.searchX+s.searchW;}
static float gapOf(WXGDockSearchSpans s,int leading) {return leading?s.capsuleX-(s.searchX+s.searchW):s.searchX-(s.capsuleX+s.capsuleW);}

int main(void) {
    const float gap=12.f;
    const WXGDockSearchRow rows[2][2]={{{27.f,381.f,68.f},{27.f,381.f,68.f}},{{27.f,368.f,62.f},{12.f,390.f,50.f}}};
    for(int r=0;r<2;r++)for(int leading=0;leading<2;leading++) {
        WXGDockSearchRow rest=rows[r][0],open=rows[r][1];
        float wc=rest.w-rest.h-gap,wf=open.w-open.h-gap;
        WXGDockSearchSpans a=WXGDockSearchLayoutRows(0.f,rest,open,gap,leading),b=WXGDockSearchLayoutRows(1.f,rest,open,gap,leading);
        /* Rest: capsule and round button (button left or right). */
        assert(near(a.height,rest.h) && near(a.capsuleW,wc) && near(a.searchW,rest.h));
        if(!leading)assert(near(a.capsuleX,rest.x) && near(a.searchX+a.searchW,rest.x+rest.w));
        else assert(near(a.searchX,rest.x) && near(a.capsuleX+a.capsuleW,rest.x+rest.w));
        /* Searching, both ways: field on the left, round close button on the right. */
        assert(near(b.height,open.h));
        if(!leading)assert(near(b.capsuleX,open.x) && near(b.capsuleW,wf) && near(b.searchW,open.h) && near(b.searchX+b.searchW,open.x+open.w));
        else assert(near(b.searchX,open.x) && near(b.searchW,wf) && near(b.capsuleW,open.h) && near(b.capsuleX+b.capsuleW,open.x+open.w));
        float previousLeftWidth=-1.f;
        for(int i=-30;i<=130;i++) {
            float t=i/100.f;
            WXGDockSearchSpans s=WXGDockSearchLayoutRows(t,rest,open,gap,leading);
            /* The gap never changes, overshoot included. */
            assert(near(gapOf(s,leading),gap));
            if(t>=0.f && t<=1.f) {
                float tc=t;
                float rowL=rest.x+(open.x-rest.x)*tc,rowR=rest.x+rest.w+(open.x+open.w-rest.x-rest.w)*tc;
                assert(near(leftX(s,leading),rowL) && near(rightEnd(s,leading),rowR));
                assert(s.capsuleW>=s.height-.01f && s.searchW>=s.height-.01f);
            } else {
                /* Past the ends: squeezed by at most a quarter of the height. */
                assert(s.capsuleW>=s.height*.75f-.01f && s.searchW>=s.height*.75f-.01f);
            }
            /* The swap (button left): the field widens steadily, no plateau. */
            if(leading && r==0 && t>=0.f && t<=1.f) {
                assert(s.searchW>=previousLeftWidth-.01f);previousLeftWidth=s.searchW;
            }
        }
    }
    /* FIX63: past the end the swap keeps moving with the spring (proportional,
       not a hard stop): every step of t moves the edge. */
    {
        WXGDockSearchRow row={27.f,368.f,62.f};
        float previous=-1e9f;
        for(int i=100;i<=110;i++) {
            WXGDockSearchSpans s=WXGDockSearchLayoutRows(i/100.f,row,row,gap,1);
            float edge=s.capsuleX;   /* the close button's left edge */
            if(i>100)assert(edge>previous+.2f);
            previous=edge;
        }
    }
    /* The swell moves only the outer ends, keeps the gap, grows the height by
       a third; nothing at rest. */
    for(int leading=0;leading<2;leading++) {
        WXGDockSearchSpans a=WXGDockSearchLayout(.6f,27.f,381.f,68.f,gap,leading),b=WXGDockSearchSwell(a,6.f,leading);
        assert(near(leftX(b,leading),leftX(a,leading)-6.f) && near(rightEnd(b,leading),rightEnd(a,leading)+6.f));
        assert(near(gapOf(b,leading),gapOf(a,leading)) && near(b.height,a.height+2.f));
        WXGDockSearchSpans c=WXGDockSearchSwell(a,0.f,leading);
        assert(c.capsuleX==a.capsuleX && c.capsuleW==a.capsuleW && c.searchX==a.searchX && c.searchW==a.searchW && c.height==a.height);
    }
    assert(WXGDockSearchSwellAmount(0.f,0.f,368.f)==0.f && WXGDockSearchSwellAmount(1.f,0.f,368.f)==0.f);
    assert(WXGDockSearchSwellAmount(.5f,7.f,368.f)>5.f && WXGDockSearchSwellAmount(.5f,7.f,368.f)<5.3f);
    assert(WXGDockSearchSwellAmount(1.09f,0.f,368.f)>2.9f && WXGDockSearchSwellAmount(1.09f,0.f,368.f)<3.0f);
    /* A row too narrow for both keeps a round capsule. */
    assert(near(WXGDockSearchCapsuleWidth(120.f,68.f,12.f),68.f));
    /* Cross-fade curves. */
    assert(WXGDockSearchTabsFade(0.f)==0.f && WXGDockSearchTabsFade(.5f)==1.f && WXGDockSearchTabsFade(1.2f)==1.f);
    assert(WXGDockSearchCloseReveal(.45f)==0.f && WXGDockSearchCloseReveal(.95f)==1.f);
    assert(WXGDockSearchFieldReveal(.35f)==0.f && WXGDockSearchFieldReveal(.9f)==1.f);
    /* The reference spring: about 9% overshoot, settled within 0.75 s, both ways. */
    for(int dir=0;dir<2;dir++) {
        double x=dir?1:0,v=0,target=dir?0:1,peak=x,settle=0;
        for(int frame=1;frame<=120;frame++) {
            WXGSpring(&x,&v,target,WXG_DOCK_SEARCH_STIFFNESS,WXG_DOCK_SEARCH_DAMPING,1./60);
            double over=dir?-x:x-1;
            if(over>(dir?-peak:peak-1))peak=x;
            if(fabs(x-target)>.01)settle=frame/60.;
        }
        double overshoot=dir?-peak:peak-1;
        assert(overshoot>.06 && overshoot<.12);
        assert(settle<.75);
        assert(x==target);
    }
    puts("PASS: dock search row (FIX63): field left / close right both ways (left button swaps, right button stays), constant gap, proportional squeeze past the ends (no plateau), row interpolation, swell, fades, spring 230/20/1.2.");
    return 0;
}
