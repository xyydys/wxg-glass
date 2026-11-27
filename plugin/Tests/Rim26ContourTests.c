#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../Sources/WXGRim26Contour.h"

typedef struct {
    double w,h,r,x,y,firstX,firstY,tx,ty,area;
    double loX,loY,hiX,hiY,deepest;
    double firstCurvature,endCurvature;
    int segments,closed,hasCurvature;
} Trace;

static void tangent(Trace *t,double dx,double dy) {
    double d=hypot(dx,dy);
    if(d<1e-9)return;
    dx/=d;dy/=d;
    if(t->r>0. && (t->tx || t->ty))assert(dx*t->tx+dy*t->ty>.9999999);
    t->tx=dx;t->ty=dy;
}
// Normalized signed curvature is scale independent. Tangency alone misses
// an inward bend and a sudden change of curvature at the end of a shoulder.
static void join(Trace *t,double curvature) {
    if(t->hasCurvature)assert(fabs(curvature-t->endCurvature)<.002);
    else {t->firstCurvature=curvature;t->hasCurvature=1;}
    t->endCurvature=curvature;
}
static void point(Trace *t,double x,double y) {
    t->loX=fmin(t->loX,x);t->loY=fmin(t->loY,y);
    t->hiX=fmax(t->hiX,x);t->hiY=fmax(t->hiY,y);
    t->area+=t->x*y-t->y*x;t->x=x;t->y=y;
    double qx=fmax(0.,fabs(x-t->w*.5)-(t->w*.5-t->r));
    double qy=fmax(0.,fabs(y-t->h*.5)-(t->h*.5-t->r));
    t->deepest=fmax(t->deepest,t->r-hypot(qx,qy));
}
static void sample(void *ctx,int op,double x1,double y1,double x2,double y2,double x,double y) {
    Trace *t=ctx;
    if(op==WXGRimMove){t->firstX=t->x=x;t->firstY=t->y=y;return;}
    if(op==WXGRimClose){x=t->firstX;y=t->firstY;t->closed++;}
    if(op!=WXGRimCubic) {
        if(t->r>0. && hypot(x-t->x,y-t->y)>1e-8)join(t,0.);
        tangent(t,x-t->x,y-t->y);point(t,x,y);return;
    }
    tangent(t,x1-t->x,y1-t->y);
    double x0=t->x,y0=t->y;
    for(int i=0;i<=16;i++) {
        double u=i/16.,v=1.-u;
        double dx=3.*(v*v*(x1-x0)+2.*v*u*(x2-x1)+u*u*(x-x2));
        double dy=3.*(v*v*(y1-y0)+2.*v*u*(y2-y1)+u*u*(y-y2));
        double ddx=6.*(v*(x2-2.*x1+x0)+u*(x-2.*x2+x1));
        double ddy=6.*(v*(y2-2.*y1+y0)+u*(y-2.*y2+y1));
        double curvature=t->r*(dx*ddy-dy*ddx)/pow(hypot(dx,dy),3.);
        assert(curvature>=-1e-7);
        if(i==0)join(t,curvature);
        if(i==16)t->endCurvature=curvature;
        point(t,v*v*v*x0+3*v*v*u*x1+3*v*u*u*x2+u*u*u*x,
                v*v*v*y0+3*v*v*u*y1+3*v*u*u*y2+u*u*u*y);
    }
    t->tx=t->ty=0;tangent(t,x-x2,y-y2);t->segments++;
}
static Trace outline(double w,double h,double r) {
    Trace t={.w=w,.h=h,.r=r,.loX=w,.loY=h};
    WXGRim26Contour(w,h,r,&t,sample);
    assert(t.closed==1 && t.area>0);
    assert(fabs(t.loX)<1e-7 && fabs(t.loY)<1e-7);
    assert(fabs(t.hiX-w)<1e-7 && fabs(t.hiY-h)<1e-7);
    if(r>0.) {
        assert(t.segments>=8 && t.hasCurvature);
        assert(fabs(t.firstCurvature-t.endCurvature)<.002);
    }
    return t;
}
// A mask whose raster ends at the material extent can discard an entire
// partially covered tip pixel. Model the worst inward scissor (ceil on the
// left, floor on the right) across every subpixel phase. Preserve every
// pixel cell intersecting the true silhouette even in that case.
static void guarded_raster(double extent,int scale) {
    double margin=WXGRim26RasterMargin(extent,scale);
    double canvas=(extent+2.*margin)*scale;
    assert(fabs(canvas-round(canvas))<1e-7);
    assert(margin*scale>=1.-1e-10 && margin*scale<1.5+1e-10);
    for(int i=0;i<256;i++) {
        double tip=i/256.,end=tip+extent*scale;
        double coveredLeft=floor(tip),coveredRight=ceil(end);
        double rasterLeft=ceil(tip-margin*scale-1e-9);
        double rasterRight=floor(end+margin*scale+1e-9);
        assert(rasterLeft<=coveredLeft && rasterRight>=coveredRight);
        // Canvas placement plus path translation gives the original two tips.
        assert(fabs((tip-margin*scale)+margin*scale-tip)<1e-9);
        assert(fabs((tip-margin*scale)+canvas-margin*scale-end)<1e-9);
    }
}
int main(void) {
    double button=41.468988;
    for(int scale=1;scale<=3;scale++) {
        guarded_raster(button,scale);guarded_raster(53.,scale);guarded_raster(82.,scale);
        guarded_raster(41.+2./3.,scale);
    }
    Trace circle=outline(button,button,button*.5);
    assert(circle.deepest<.0001);
    Trace capsule=outline(120,44,22);
    assert(fabs(capsule.deepest-22*.017)<.03);
    Trace inner=outline(120-2/3.,44-2/3.,22-1/3.);
    assert(inner.area<capsule.area);
    Trace vertical=outline(44,120,22);
    assert(fabs(vertical.area-capsule.area)<1e-7);
    outline(76.197,button,16.33);
    outline(90,44,0.);
    outline(button+.033,button,button*.5);
    // Diagnostic 19's 53 and 82 pt chat titles, the full interval around
    // them, and several insets of the nested antialiased rim bands.
    for(int width=42;width<=125;width++) {
        const double insets[]={0.,1./3.,1.005,4.};
        double previousArea=INFINITY;
        for(unsigned i=0;i<sizeof(insets)/sizeof(*insets);i++) {
            double d=insets[i];
            Trace band=outline(width-2.*d,button-2.*d,button*.5-d);
            assert(band.area<previousArea);
            previousArea=band.area;
        }
    }
    puts("PASS: iOS 26 inner and outer vector contours, convexity and curvature continuity across compact widths, measured dip and fractional circles");
    return 0;
}
