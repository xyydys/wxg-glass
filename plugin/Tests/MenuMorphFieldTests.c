#include "../Sources/WXGMenuMorphField.h"
#include "../Sources/WXGRim26.h"
#include "../Sources/WXGMenuMorph.h"
#include <assert.h>
#include <stdio.h>

typedef struct { int contours, points, closed; } ContourCount;

static void countContour(WXGMenuMorphContourAction action, float x, float y, void *context) {
    ContourCount *count = context;
    assert(isfinite(x) && isfinite(y));
    if (action == WXGMenuMorphContourMove) count->contours++;
    if (action == WXGMenuMorphContourLine) count->points++;
    if (action == WXGMenuMorphContourClose) count->closed++;
}

static ContourCount trace(WXGMenuMorphFieldBox menu, WXGMenuMorphFieldBox trigger, float smoothing) {
    WXGMenuMorphField field;
    WXGMenuMorphFieldBuild(&field, menu, menu.radius, trigger, smoothing, 5.f);
    assert(field.width <= WXGMenuMorphFieldSide && field.height <= WXGMenuMorphFieldSide);
    for (int x = 0; x < field.width; x++) {
        assert(field.values[x] >= 0);
        assert(field.values[(field.height - 1) * field.width + x] >= 0);
    }
    for (int y = 0; y < field.height; y++) {
        assert(field.values[y * field.width] >= 0);
        assert(field.values[y * field.width + field.width - 1] >= 0);
    }
    ContourCount count = {0};
    WXGMenuMorphFieldTrace(&field, countContour, &count);
    assert(count.contours == count.closed);
    return count;
}

// The rectangular underlay used to remain visible on each side after its
// source lobe was absorbed. Check the real, spring-driven intermediate frame.
static void testMovingMaterial(void) {
    WXGMenuBox plus={340,64,44,44}, menu={164,64,220,230};
    WXGMenuMorph motion;
    WXGMenuMorphInitialize(&motion,plus,menu,34.,plus,true);
    WXGMenuMorphSetExpanded(&motion,true);
    for(int i=0;i<17;i++)WXGMenuMorphAdvance(&motion,1./120.);
    WXGMenuMorphFrame m=motion.frame;
    WXGMenuMorphField field;
    WXGMenuMorphFieldBuild(&field,(WXGMenuMorphFieldBox){m.bounds.x,m.bounds.y,m.bounds.w,m.bounds.h,m.radiusX},
        m.radiusY,(WXGMenuMorphFieldBox){m.sourceLobe.x,m.sourceLobe.y,m.sourceLobe.w,m.sourceLobe.h,m.sourceRadius},m.smoothing,5.f);
    ContourCount outline={0};
    WXGMenuMorphFieldTrace(&field,countContour,&outline);
    assert(outline.contours==1 && outline.closed==1);
    float cy=m.bounds.y+.5f*m.bounds.h,cx=m.bounds.x+.5f*m.bounds.w;
    assert(WXGMenuMorphFieldRead(&field,cx,cy).distance < -20.f);
    assert(WXGMenuMorphFieldRead(&field,m.bounds.x,cy).distance > .3f);
    WXGRim26Shape rim={.height=1.,.curve=.7,.angle=45.,.key=1.05,.fill=1.,.spread=1.,.ring=.15};
    int entries=0,exits=0; bool wasInside=false;
    for(float x=field.x;x<field.x+(field.width-1)*field.step;x+=.125f) {
        WXGMenuMorphFieldSample sample=WXGMenuMorphFieldRead(&field,x,cy);
        bool inside=sample.distance<0;
        entries+=inside && !wasInside; exits+=!inside && wasInside; wasInside=inside;
        double alpha=WXGRim26Alpha(-sample.distance,sample.dx,sample.dy,rim);
        if(sample.distance < -1. || !inside)assert(alpha==0.);
        for(int dark=0;dark<2;dark++) {
            float matrix[20];
            WXGRim26Matrix(dark?1.35:.174,dark?3.:1.51,dark?.15:.847,matrix);
            double face[3]={.12,.28,.44},out[3];
            WXGRim26Colour(matrix,face,alpha,out);
            if(!alpha)for(int k=0;k<3;k++)assert(out[k]==face[k]);
        }
    }
    assert(entries==1 && exits==1);
    // An elliptically scaled menu and its transposed copy must have the same
    // SDF when sampled at transposed positions, with or without smoothing.
    for(int blur=0;blur<=10;blur+=10) {
        WXGMenuMorphField swapped;
        WXGMenuMorphFieldBuild(&field,(WXGMenuMorphFieldBox){0,0,80,140,18},54,(WXGMenuMorphFieldBox){0},blur,5);
        WXGMenuMorphFieldBuild(&swapped,(WXGMenuMorphFieldBox){0,0,140,80,54},18,(WXGMenuMorphFieldBox){0},blur,5);
        for(int y=0;y<140;y+=3)for(int x=0;x<80;x+=3) {
            float d=WXGMenuMorphFieldRead(&field,x,y).distance, t=WXGMenuMorphFieldRead(&swapped,y,x).distance;
            assert(fabsf(d-t)<.04f);
        }
    }
}
int main(void) {
    testMovingMaterial();
    WXGMenuMorphFieldBox menu = {20, 55, 190, 220, 27};
    WXGMenuMorphFieldBox trigger = {105, 8, 40, 40, 20};
    WXGMenuMorphFieldBox absorbed = {100, 150, 30, 30, 15};
    assert(trace(menu, trigger, 0).contours == 2);
    assert(trace(menu, trigger, 14).contours == 1);
    assert(trace(menu, absorbed, 10).contours == 1);
    for (int step = 0; step <= 240; step++) {
        float p = step / 240.0f;
        WXGMenuMorphFieldBox source = {165 - 65 * p, 43 + 130 * p, 44 - 33 * p, 44 - 33 * p, 22 - 16.5f * p};
        WXGMenuMorphFieldBox incoming = {164 - 120 * p, 43 + 30 * p, 12 + 160 * p, 12 + 245 * p, 6 + 70 * p};
        ContourCount count = trace(incoming, source, 46 * p * (1 - p));
        assert(count.contours >= 1 && count.contours <= 2 && count.points >= 12);
    }
    puts("MenuMorphFieldTests: separated, joined and absorbed lobes trace cleanly over the animation.");
    return 0;
}
