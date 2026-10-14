#ifndef WXG_DOCK_SEARCH_LAYOUT_H
#define WXG_DOCK_SEARCH_LAYOUT_H
#include <math.h>
/* FIX60/61: the dock row with a search button. At rest the tab capsule and
   a round search button share the row (the dock's width setting is the
   whole row). Searching, the button widens into a search field and the
   capsule narrows into a round close button at its outer end, inside the
   search row (FIX61: its own width and height, both shapes as tall as it).
   One spring value t drives everything (0 = tabs, 1 = searching), so the
   gap between the two stays constant. The spring overshoots: past an end,
   the shape that shrinks is squeezed a little, softly (FIX63). FIX63: the
   field always ends on the left and the close button on the right. */
typedef struct { float x,w,h; } WXGDockSearchRow;      /* left edge, width, height */
typedef struct { float capsuleX,capsuleW,searchX,searchW,height; } WXGDockSearchSpans;

static inline float WXGDockSearchCapsuleWidth(float rowW,float d,float gap) {
    float w=rowW-d-gap;
    return w>d?w:d;
}
static inline float WXGDockSearchLerp(float a,float b,float t) {return a+(b-a)*t;}
/* FIX63: a past-the-end spring value pushes softly (tanh) instead of hitting
   a hard stop, so nothing stalls at the turning point. `limit` is the most
   it can give. */
static inline float WXGDockSearchSoft(float over,float limit) {
    return limit>0.f && over>0.f?limit*tanhf(over/limit):0.f;
}
/* Swap (button on the left, mirrored from this): the capsule on the left
   narrows to a round button at its left end, the round button on the right
   widens leftwards into the field. Past either end the shrinking shape is
   squeezed by about a third of the overshoot (never more than a quarter of
   its height) and the growing one follows, the gap unchanged: it moves with
   the spring the whole time, no plateau. */
static inline WXGDockSearchSpans WXGDockSearchSwapRight(float t,WXGDockSearchRow rest,WXGDockSearchRow open,float gap) {
    float tc=t<0.f?0.f:t>1.f?1.f:t;
    float left=WXGDockSearchLerp(rest.x,open.x,tc),right=WXGDockSearchLerp(rest.x+rest.w,open.x+open.w,tc);
    float h=WXGDockSearchLerp(rest.h,open.h,tc),squeeze=h*.25f;
    float restEnd=rest.x+WXGDockSearchCapsuleWidth(rest.w,rest.h,gap),openEnd=open.x+open.h;
    float cr=WXGDockSearchLerp(restEnd,openEnd,t),sl;
    if(t>1.f){cr=left+h-WXGDockSearchSoft((openEnd-cr)*.35f,squeeze);sl=cr+gap;}
    else if(t<0.f){sl=right-h+WXGDockSearchSoft((cr-restEnd)*.35f,squeeze);cr=sl-gap;}
    else {
        sl=cr+gap;
        /* Both stay at least round even for a cramped search row. */
        if(cr<left+h){cr=left+h;sl=cr+gap;}
        if(sl>right-h){sl=right-h;if(cr>sl-gap)cr=fmaxf(left+h,sl-gap);}
    }
    WXGDockSearchSpans s={left,cr-left,sl,right-sl,h};
    return s;
}
/* Stay (button on the right): no swap. The capsule on the left becomes the
   field, the round button on the right becomes the close button; both go
   from the dock's row to the search row (spring past the ends included). */
static inline WXGDockSearchSpans WXGDockSearchStay(float t,WXGDockSearchRow rest,WXGDockSearchRow open,float gap) {
    float left=WXGDockSearchLerp(rest.x,open.x,t),right=WXGDockSearchLerp(rest.x+rest.w,open.x+open.w,t);
    float h=WXGDockSearchLerp(rest.h,open.h,t);
    if(h<1.f)h=1.f;
    float field=right-left-h-gap;
    if(field<h)field=h;
    WXGDockSearchSpans s={left,field,left+field+gap,right-(left+field+gap),h};
    if(s.searchW<h){s.searchW=h;}
    return s;
}
/* Both ways the search field ends up on the left and the close button on the
   right (FIX63, user): button on the left swaps, button on the right stays. */
static inline WXGDockSearchSpans WXGDockSearchLayoutRows(float t,WXGDockSearchRow rest,WXGDockSearchRow open,float gap,int searchLeading) {
    if(!searchLeading)return WXGDockSearchStay(t,rest,open,gap);
    /* Mirrored (x -> -x), laid out, mirrored back. */
    WXGDockSearchRow r={-(rest.x+rest.w),rest.w,rest.h},o={-(open.x+open.w),open.w,open.h};
    WXGDockSearchSpans m=WXGDockSearchSwapRight(t,r,o,gap);
    WXGDockSearchSpans s={-(m.capsuleX+m.capsuleW),m.capsuleW,-(m.searchX+m.searchW),m.searchW,m.height};
    return s;
}
/* One row for both states (FIX60). */
static inline WXGDockSearchSpans WXGDockSearchLayout(float t,float rowX,float rowW,float d,float gap,int searchLeading) {
    WXGDockSearchRow row={rowX,rowW,d};
    return WXGDockSearchLayoutRows(t,row,row,gap,searchLeading);
}
/* FIX62: the whole row swells a little with the spring (not only the two
   ends that meet): the outer ends move out by `swell` points and both shapes
   grow by a third of that in height (centred). 0 leaves the spans as they are. */
static inline WXGDockSearchSpans WXGDockSearchSwell(WXGDockSearchSpans s,float swell,int searchLeading) {
    if(!(swell>0.f))return s;
    if(searchLeading){s.searchX-=swell;s.searchW+=swell;s.capsuleW+=swell;}
    else {s.capsuleX-=swell;s.capsuleW+=swell;s.searchW+=swell;}
    s.height+=swell/3.f;
    return s;
}
/* The swell for a spring at t moving at v (per second) in a row `rowW`
   wide: with its speed (about 1.4% of the row at full speed) and with the
   overshoot past either end. */
static inline float WXGDockSearchSwellAmount(float t,float v,float rowW) {
    float over=t>1.f?t-1.f:t<0.f?-t:0.f,speed=fabsf(v)/7.f;
    if(speed>1.f)speed=1.f;
    return rowW*(.014f*speed+.09f*over);
}
static inline float WXGDockSearchSmooth(float a,float b,float x) {
    float t=(x-a)/(b-a);
    t=t<0.f?0.f:t>1.f?1.f:t;
    return t*t*(3.f-2.f*t);
}
/* Content cross-fade, from the clamped progress: the tabs (icons, pill)
   fade out over the first half, the close glyph and the field's text come
   in over the second half. */
static inline float WXGDockSearchTabsFade(float t) {return WXGDockSearchSmooth(0.f,.5f,t);}
static inline float WXGDockSearchCloseReveal(float t) {return WXGDockSearchSmooth(.45f,.95f,t);}
static inline float WXGDockSearchFieldReveal(float t) {return WXGDockSearchSmooth(.35f,.9f,t);}
/* The React reference's spring (stiffness 230, damping 20, mass 1.2) for a
   unit-mass integrator: k / m and c / m. */
#define WXG_DOCK_SEARCH_STIFFNESS (230.0/1.2)
#define WXG_DOCK_SEARCH_DAMPING (20.0/1.2)
#endif
