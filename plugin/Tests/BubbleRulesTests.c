#include "../Sources/WXGBubbleRules.h"
#include <assert.h>
#include <stdio.h>

static int near(double a,double b) {return fabs(a-b)<1e-9;}

int main(void) {
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
    puts("PASS: liquid bubble (FIX82): one-line radius kept by taller bubbles, larger text, 40 pt floor, width cap, one-line class, direction from the tail.");
    return 0;
}
