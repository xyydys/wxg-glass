#include "../Sources/WXGBubbleRules.h"
#include "../Sources/WXGBubbleQuoteRules.h"
#include <assert.h>
#include <stdio.h>

static int near(double a,double b) {return fabs(a-b)<1e-9;}

static void testQuoteDivider(void) {
    assert(WXGBubbleQuoteDividerDistinct(NAN,42.));
    assert(!WXGBubbleQuoteDividerDistinct(42.,44.99));
    assert(WXGBubbleQuoteDividerDistinct(42.,45.));
    assert(!WXGBubbleQuoteDividerDistinct(42.,NAN));
    WXGBubbleSpan text={50.,76.};
    assert(near(WXGBubbleQuoteDividerY(text,(WXGBubbleSpan){3.,40.},(WXGBubbleSpan){6.,37.}),45.));
    assert(near(WXGBubbleQuoteDividerY(text,(WXGBubbleSpan){72.,120.},(WXGBubbleSpan){80.,116.}),78.));
    assert(isnan(WXGBubbleQuoteDividerY(text,(WXGBubbleSpan){74.,110.},(WXGBubbleSpan){78.,111.})));
    assert(isnan(WXGBubbleQuoteDividerY(text,(WXGBubbleSpan){NAN,NAN},(WXGBubbleSpan){84.,100.})));
    for(int scale=2;scale<=3;scale++) {
        WXGBubbleBox line=WXGBubbleQuoteDividerFrame(160.,110.,45.2,scale);
        assert(near(line.x,12.) && near(line.w,136.) && near(line.h*scale,1.));
        assert(near((line.y+.5*line.h)*scale,round(45.2*scale)));
    }
    assert(!WXGBubbleQuoteDividerFrame(44.,50.,8.,2.).w);
    assert(!WXGBubbleQuoteDividerFrame(44.,50.,42.,2.).w);
    assert(!WXGBubbleQuoteDividerFrame(43.9,50.,20.,2.).w);
    assert(near(WXGBubbleQuoteDividerFrame(44.,50.,20.,2.).w,20.));
}

int main(void) {
    testQuoteDivider();
    for(int index=0;index<4;index++) {
        WXGBubbleSpan piece=WXGBubbleLocalSlice(0,62,20,index>0,index<3);
        assert(near(piece.min,index==0?0:-20));
        assert(near(piece.max,index==3?62:82));
    }
    WXGBubbleSpan single=WXGBubbleLocalSlice(0,102,20,0,0);
    assert(near(single.min,0) && near(single.max,102));
    /* One line at the standard size: a capsule; taller bubbles keep the same radius. */
    assert(near(WXGBubbleRadius(120,40,40),20));
    assert(near(WXGBubbleRadius(240,84,40),20) && near(WXGBubbleRadius(240,300,40),20));
    /* Larger text: the one-line height is 48, every bubble then uses 24. */
    assert(near(WXGBubbleRadius(160,48,48),24) && near(WXGBubbleRadius(260,140,48),24));
    /* Never below the 40 pt reference; nothing observed yet: 40. */
    assert(near(WXGBubbleReference(36),40) && near(WXGBubbleReference(0),40) && near(WXGBubbleRadius(200,90,0),20));
    /* A narrow bubble is capped at half its width. */
    assert(near(WXGBubbleRadius(30,40,40),15));
    assert(WXGBubbleRadius(0,40,40)==0 && WXGBubbleRadius(40,0,40)==0);
    /* The one-line class. */
    assert(WXGBubbleOneLine(40) && WXGBubbleOneLine(48) && WXGBubbleOneLine(56) && WXGBubbleOneLine(34));
    assert(!WXGBubbleOneLine(33.9) && !WXGBubbleOneLine(60) && !WXGBubbleOneLine(59));
    /* Direction from the image: incoming tails reach left of the body. */
    assert(WXGBubbleOutgoingFromImage(0) && WXGBubbleOutgoingFromImage(-.4) && !WXGBubbleOutgoingFromImage(-5));
    /* Two lines at normal size are never their own radius reference. */
    assert(!WXGBubbleOneLine(61) && near(WXGBubbleRadius(160,61,40),20));
    assert(near(WXGBubbleRadius(160,84,56),28));
    WXGBubbleBox first={64,100,236,84},next={65,185,235,90};
    assert(WXGBubbleAdjacentBoxes(first,next,0));
    next.y=203;next.w=170;
    assert(!WXGBubbleAdjacentBoxes(first,next,0) && WXGBubbleAdjacentBoxes(first,next,1));
    next.x=282;
    assert(!WXGBubbleAdjacentBoxes(first,next,1));
    next=(WXGBubbleBox){64,370,236,84};
    assert(!WXGBubbleAdjacentBoxes(first,next,1));

    /* Replacement-font overshoot stays with the original renderer. A lower
       translation can start slightly inside the skin after pixel rounding. */
    WXGBubbleBox textSkin={30,20,240,58};
    assert(!WXGBubbleTextBelowSkin(textSkin,(WXGBubbleBox){42,27,214,58}));
    assert(WXGBubbleTextBelowSkin(textSkin,(WXGBubbleBox){42,76,214,44}));
    assert(WXGBubbleTextBelowSkin(textSkin,(WXGBubbleBox){42,90,214,620}));
    assert(!WXGBubbleTextBelowSkin(textSkin,(WXGBubbleBox){282,90,40,30}));

    WXGBubbleSpan family={100,8200},none={0,0};
    WXGBubbleSpan flat={2250,3170},viewport={2300,3100};
    assert(WXGBubbleExtendIndexedSpan(&flat,viewport,1,1) && flat.min<2200 && flat.max>3200);
    flat=(WXGBubbleSpan){2350,3170};
    assert(!WXGBubbleExtendIndexedSpan(&flat,viewport,1,1));
    assert(WXGBubbleExtendIndexedSpan(&flat,viewport,0,1) && near(flat.min,2350) && flat.max>3200);
    WXGBubbleSpan top=WXGBubbleRenderSpan(family,(WXGBubbleSpan){0,800},none);
    assert(near(top.min,100) && top.max>800 && top.max<1700);
    WXGBubbleSpan middle=WXGBubbleRenderSpan(family,(WXGBubbleSpan){2300,3100},top);
    assert(middle.min<2100 && middle.max>3300 && middle.max-middle.min<=1600);
    WXGBubbleSpan moved=WXGBubbleRenderSpan(family,(WXGBubbleSpan){2390,3190},middle);
    assert(near(middle.min,moved.min) && near(middle.max,moved.max));
    WXGBubbleSpan end=WXGBubbleRenderSpan(family,(WXGBubbleSpan){7800,8600},middle);
    assert(end.min<7800 && near(end.max,8200));
    puts("PASS: one-line and two-line contours, adjacent fragment geometry, bounded continuous long-message surface.");
    return 0;
}
