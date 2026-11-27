#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../Sources/WXGRim26Mask.h"

// Independent reference: exact horizontal circle chords, integrated vertically
// at much higher resolution than the production vector scan converter.
static double diskCoverage(int x,int y,double cx,double cy,double r) {
    if(r<=0.)return 0.;
    double center=hypot(x+.5-cx,y+.5-cy);
    if(center<r-.708)return 1.;
    if(center>r+.708)return 0.;
    const int steps=1024;
    double sum=0.;
    for(int k=0;k<steps;k++) {
        double dy=y+(k+.5)/steps-cy,dx=sqrt(fmax(0.,r*r-dy*dy));
        sum+=fmax(0.,fmin(x+1.,cx+dx)-fmax(x,cx-dx));
    }
    return sum/steps;
}

static double peakError,oldPeakError;
static void checkCircle(double diameter,double scale,double phaseX,double phaseY,WXGRim26Shape shape) {
    WXGRim26MaskAxis x=WXGRim26MaskAxisFor(phaseX/scale,diameter,diameter*.5,shape.height,scale);
    WXGRim26MaskAxis y=WXGRim26MaskAxisFor(phaseY/scale,diameter,diameter*.5,shape.height,scale);
    uint8_t *alpha=malloc((size_t)x.pixels*y.pixels);
    assert(alpha && WXGRim26DrawMask(alpha,x,y,diameter*.5,scale,shape));
    double radius=diameter*.5*scale,cx=x.leading*scale+radius,cy=y.leading*scale+radius;
    WXGRim26Bands l=WXGRim26BandsFor(0,shape,scale),p=WXGRim26BandsFor(1,shape,scale);
    for(int j=0;j<y.pixels;j++)for(int i=0;i<x.pixels;i++) {
        double dx=i+.5-cx,dy=j+.5-cy,dist=hypot(dx,dy);
        double output=alpha[(size_t)j*x.pixels+i]/255.;
        if(dist>radius+.708 || dist<radius-l.width[l.count-1]*scale-.708) {
            assert(output==0.);
            continue;
        }
        double light=WXGRim26Along(dx/dist,dy/dist,shape);
        double outer=diskCoverage(i,j,cx,cy,radius),previous=outer;
        double expected=0.,oldLight=0.,oldPlain=0.;
        for(int k=0;k<l.count;k++) {
            double inner=diskCoverage(i,j,cx,cy,radius-l.width[k]*scale);
            expected+=(previous-inner)*(p.level[k]+(1.-p.level[k])*l.level[k]*light);
            double nested=outer-inner;
            oldLight+=(1.-oldLight)*nested*l.alpha[k];
            oldPlain+=(1.-oldPlain)*nested*p.alpha[k];
            previous=inner;
        }
        double old=oldPlain+(1.-oldPlain)*light*oldLight;
        peakError=fmax(peakError,fabs(expected-output));
        oldPeakError=fmax(oldPeakError,fabs(expected-old));
    }
    free(alpha);
}

// Compare a stretched tile against an independent full-size draw byte for byte.
// The central texel may only be repeated in an optically flat straight run.
static void checkTile(double w,double h,double r,double scale,WXGRim26Shape s) {
    WXGRim26MaskAxis x=WXGRim26MaskAxisFor(.27,w,r,s.height,scale),y=WXGRim26MaskAxisFor(-.56,h,r,s.height,scale);
    WXGRim26MaskAxis fullX=x,fullY=y;
    if(x.cap){fullX.cap=0;fullX.material=w;fullX.pixels=(int)lround((w+x.leading+x.trailing)*scale);}
    if(y.cap){fullY.cap=0;fullY.material=h;fullY.pixels=(int)lround((h+y.leading+y.trailing)*scale);}
    uint8_t *tile=malloc((size_t)x.pixels*y.pixels),*full=malloc((size_t)fullX.pixels*fullY.pixels);
    assert(tile && full && WXGRim26DrawMask(tile,x,y,r,scale,s) && WXGRim26DrawMask(full,fullX,fullY,r,scale,s));
    for(int j=0;j<fullY.pixels;j++)for(int i=0;i<fullX.pixels;i++) {
        int tx=x.cap && i>=x.cap?(int)fmax(x.cap,i-(fullX.pixels-x.pixels)):i;
        int ty=y.cap && j>=y.cap?(int)fmax(y.cap,j-(fullY.pixels-y.pixels)):j;
        int diff=tile[(size_t)ty*x.pixels+tx]-full[(size_t)j*fullX.pixels+i];
        assert(abs(diff)<=1);
        if(i==0 || j==0 || i==fullX.pixels-1 || j==fullY.pixels-1)
            assert(full[(size_t)j*fullX.pixels+i]==0);
    }
    free(tile);free(full);
}

static void guardedRaster(double length,int scale) {
    for(int i=0;i<256;i++) {
        double origin=(i/256.-.5)/scale;
        WXGRim26MaskAxis a=WXGRim26MaskAxisFor(origin,length,length*.5,1.,scale);
        double left=(origin-a.leading)*scale;
        double right=(origin+length+a.trailing)*scale;
        assert(fabs(left-round(left))<1e-8 && fabs(right-round(right))<1e-8);
        assert(a.leading*scale>=1.-1e-8 && a.trailing*scale>=1.-1e-8);
        assert(fabs(right-left-a.pixels)<1e-8);
        assert(fabs(left+a.leading*scale-origin*scale)<1e-8);
        assert(fabs(right-a.trailing*scale-(origin+length)*scale)<1e-8);
    }
}

int main(void) {
    WXGRim26Shape s={1.005,.70,45.,1.05,1.,1.,.04,0.,.1886};
    for(int scale=1;scale<=3;scale++) {
        guardedRaster(41.468988,scale);guardedRaster(53.,scale);guardedRaster(82.,scale);
        guardedRaster(41.+2./3.,scale);
        for(int phase=0;phase<8;phase++)
            checkCircle(41.468988,scale,phase/8.,((3*phase)%8)/8.,s);
        checkTile(53.,41.468988,20.734494,scale,s);
        checkTile(82.,41.468988,20.734494,scale,s);
        checkTile(320.,44.,22.,scale,s);
        checkTile(44.,320.,22.,scale,s);
        checkTile(313.,240.,8.2,scale,s);
        checkTile(92.,37.,0.,scale,s);
    }
    // The measured profile QR button, including its position on the screen grid.
    double diameter=41.468988,radiusPixels=diameter*1.5;
    checkCircle(diameter,3.,118.28+.5-radiusPixels,113.49+.5-radiusPixels,s);
    WXGRim26Shape flat=s;flat.floor=1.;flat.key=flat.fill=1.;flat.ring=1.;flat.height=.3;
    checkCircle(41.468988,3,.5,.25,flat);
    assert(peakError<.025 && oldPeakError>.1);
    printf("PASS: resolved vector rim, worst fractional-pixel alpha error %.4f vs nested %.4f; circle at 1/2/3x and stretch tiles verified.\n",peakError,oldPeakError);
    return 0;
}
