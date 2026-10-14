#include "../Sources/WXGPressStretch.h"
#include <assert.h>
#include <stdio.h>

static int near(double a,double b,double e) {return fabs(a-b)<e;}

int main(void) {
    const WXGStretchStyle legacy={.6,1,0,0};
    /* Rubber band: zero at rest, rising, always short of the limit. */
    assert(WXGRubberBand(0,16)==0 && WXGRubberBand(10,0)==0);
    double previous=0;
    for(int i=1;i<=400;i++){double r=WXGRubberBand(i,16);assert(r>previous && r<16);previous=r;}
    assert(WXGRubberBand(30,16)>9 && WXGRubberBand(30,16)<11);
    WXGStretchState s={0};
    WXGStretchTarget(&s,30,40,16);
    assert(near(hypot(s.targetX,s.targetY),WXGRubberBand(50,16),1e-9) && near(s.targetX/s.targetY,.75,1e-9));

    /* At rest the pose is the press pose. */
    WXGButtonPressPose none={1,1,0,0},press=WXGButtonPress(1,0,0,0);
    WXGStretchPose m=WXGStretchPoseMake(press,0,0,44,44,legacy);
    assert(m.a==press.scaleX && m.d==press.scaleY && m.b==0 && m.c==0 && m.tx==press.offsetX && m.ty==press.offsetY);
    /* Pulled right on a round button: longer by amount x pull, half that
       narrower, no shear; FIX70: it hardly moves: the far (left) side stays
       within 10% of the lengthening, the near side reaches out. */
    m=WXGStretchPoseMake(none,10,0,44,44,legacy);
    assert(near(m.a*44,44+6,1e-9) && near(m.d*44,44-3,1e-9) && m.b==0 && m.c==0 && near(m.tx,6*WXG_STRETCH_SHIFT,1e-9) && m.ty==0);
    {double left=-22*m.a+m.tx,right=22*m.a+m.tx;assert(fabs(left+22)<=.1*6+1e-9 && right-22>5);}
    /* However far it is pulled, the centre moves at most shift x amount x limit. */
    WXGStretchTarget(&s,500,0,16);m=WXGStretchPoseMake(none,s.targetX,s.targetY,200,44,legacy);
    assert(m.tx<WXG_STRETCH_SHIFT*.6*16+1e-9);
    /* The same pull on a wide capsule: the same points, not the same ratio. */
    m=WXGStretchPoseMake(none,10,0,200,44,legacy);
    assert(near(m.a*200,206,1e-9) && near(m.d*44,41,1e-9));
    m=WXGStretchPoseMake(none,0,10,200,44,legacy);
    assert(near(m.d*44,50,1e-9) && near(m.a*200,197,1e-9));
    /* Diagonal: symmetric stretch (b == c), longer along the pull than across. */
    m=WXGStretchPoseMake(none,7,7,44,44,legacy);
    assert(near(m.b,m.c,1e-12) && m.b>0);
    double ux=sqrt(.5),along=(ux*(m.a*ux+m.c*ux)+ux*(m.b*ux+m.d*ux)),across=(ux*(m.a*ux-m.c*ux)-ux*(m.b*ux-m.d*ux));
    assert(along>1 && across<1);
    /* Children move with the body: a child at the body's centre just moves by
       the pose's offset; one off centre follows the matrix. */
    double tx,ty;WXGStretchChildOffset(m,0,0,&tx,&ty);assert(tx==m.tx && ty==m.ty);
    m=WXGStretchPoseMake(none,10,0,44,44,legacy);
    WXGStretchChildOffset(m,8,0,&tx,&ty);assert(near(8+tx,m.a*8+m.tx,1e-12) && near(ty,0,1e-12));
    s=(WXGStretchState){0};

    /* Springs: following settles on the target without much overshoot; let go
       it overshoots by about a quarter and is home within 0.8 s. */
    s=(WXGStretchState){0};s.tracking=1;s.targetX=10;
    double peak=0;for(int i=0;i<60;i++){WXGStretchStep(&s,1./60);if(s.x>peak)peak=s.x;}
    assert(near(s.x,10,.05) && peak<10.6);
    s.tracking=0;s.targetX=0;double low=0,settle=0;
    for(int i=1;i<=90;i++){WXGStretchStep(&s,1./60);if(s.x<low)low=s.x;if(fabs(s.x)>.1)settle=i/60.;}
    assert(low<-1.2 && low>-3.5 && settle<.8);
    for(int i=0;i<120;i++)WXGStretchStep(&s,1./60);
    assert(WXGStretchResting(&s));

    /* Dock end: the far end stays put, the near end moves out by o, the bar
       slightly thinner; the left side mirrors it. */
    double x0=40,x1=408,cx=224,h=59;
    WXGStretchPose d=WXGDockEndStretchPose(12,1,x0,x1,cx,h);
    assert(near(d.a*(x0-cx)+cx+d.tx,x0,1e-9) && near(d.a*(x1-cx)+cx+d.tx,x1+12,1e-9) && d.d<1 && d.b==0 && d.c==0);
    d=WXGDockEndStretchPose(12,-1,x0,x1,cx,h);
    assert(near(d.a*(x1-cx)+cx+d.tx,x1,1e-9) && near(d.a*(x0-cx)+cx+d.tx,x0-12,1e-9));
    d=WXGDockEndStretchPose(-3,1,x0,x1,cx,h);
    assert(d.a<1 && d.d>1 && near(d.a*(x0-cx)+cx+d.tx,x0,1e-9));
    d=WXGDockEndStretchPose(0,1,x0,x1,cx,h);
    assert(d.a==1 && d.d==1 && d.tx==0);
    /* FIX73: reach is the posed rounded rectangle's exact half extent. */
    {
        double rx,ry;WXGStretchPose id={1,0,0,1,0,0};
        WXGStretchReach(id,200,40,20,&rx,&ry);assert(near(rx,100,1e-9) && near(ry,20,1e-9));
        WXGStretchPose rot={cos(.3),sin(.3),-sin(.3),cos(.3),0,0};   /* a circle turned is the same circle */
        WXGStretchReach(rot,40,40,20,&rx,&ry);assert(near(rx,20,1e-9) && near(ry,20,1e-9));
        WXGStretchPose wide=WXGStretchPoseMake(none,10,0,200,40,legacy);
        WXGStretchReach(wide,200,40,20,&rx,&ry);assert(near(rx,103,1e-9) && near(ry,18.5,1e-9));
    }
    /* FIX73: the input pill (300 x 36) in a panel that clips 6 pt above and
       below it. Pulled up it may only stretch until its top reaches the clip;
       sideways (room enough) the whole pull; already outside: no tighter
       than at rest; no clip: everything. */
    {
        double w=300,h=36,r=18;const WXGStretchStyle amount=legacy;
        WXGButtonPressPose p=WXGButtonPress(1,0,-1,0);
        double box[4]={-160,-24,160,24};
        double k=WXGStretchFit(p,0,-16,w,h,r,amount,box[0],box[1],box[2],box[3]);
        assert(k>0 && k<1);
        WXGStretchPose fit=WXGStretchPoseMake(p,0,-16*k,w,h,amount);
        double rx,ry;WXGStretchReach(fit,w,h,r,&rx,&ry);
        assert(fit.ty-ry>=-24-1e-4 && fit.ty-ry<-24+.05);
        assert(WXGStretchFit(none,30,0,w,h,r,amount,-400,-24,400,24)==1);
        assert(WXGStretchFit(none,0,0,w,h,r,amount,-1,-1,1,1)==1);
        /* The pressed pill already reaches past a tight box: the pull is
           measured against where the press alone takes it. */
        double tight=WXGStretchFit(p,0,-16,w,h,r,amount,-150,-18,150,18);
        assert(tight>=0 && tight<1);
        WXGStretchPose rest=WXGStretchPoseMake(p,0,0,w,h,amount),pulled=WXGStretchPoseMake(p,0,-16*tight,w,h,amount);
        double rrx,rry;WXGStretchReach(rest,w,h,r,&rrx,&rry);WXGStretchReach(pulled,w,h,r,&rx,&ry);
        assert(pulled.ty-ry>=fmin(-18,rest.ty-rry)-1e-4);
        /* Monotonic: a larger box never allows less. */
        double last=0;
        for(int i=0;i<=20;i++){double e=24+i;double kk=WXGStretchFit(p,8,-16,w,h,r,amount,-150-e,-e,150+e,e);assert(kk+1e-9>=last);last=kk;}
        assert(WXGStretchFit(p,0,-16,w,h,r,amount,-1e9,-1e9,1e9,1e9)==1);
    }
    /* FIX80: not round: only along x and y (no shear) at `capsule` of the
       amount; a diagonal pull stretches each axis by its own part, and the
       centre's move is continuous through a zero component. */
    {
        const WXGStretchStyle half={.6,.5,0,0};
        WXGStretchPose c=WXGStretchPoseMake(none,7,-7,200,44,half);
        assert(c.b==0 && c.c==0 && c.a>1 && c.d>1 && c.tx>0 && c.ty<0);
        c=WXGStretchPoseMake(none,10,0,200,44,half);
        assert(near(c.a*200,203,1e-9) && near(c.d*44,42.5,1e-9));
        WXGStretchPose l=WXGStretchPoseMake(none,1e-7,10,200,44,half),r=WXGStretchPoseMake(none,-1e-7,10,200,44,half);
        assert(near(l.tx,r.tx,1e-6) && l.b==0 && l.c==0);
        /* a round button still stretches along the diagonal */
        WXGStretchPose o=WXGStretchPoseMake(none,7,-7,44,44,half);assert(fabs(o.b)>1e-3);
        assert(WXGStretchRound(44,44) && WXGStretchRound(46,44) && !WXGStretchRound(60,44));
    }
    /* FIX80: the lengthening eases into the maximum and never passes it;
       small pulls are almost the plain amount. */
    {
        const WXGStretchStyle capped={.6,1,8,0};
        double last=0;
        for(int i=1;i<=200;i++) {
            WXGStretchPose c=WXGStretchPoseMake(none,i*.5,0,44,44,capped);
            double e=c.a*44-44;assert(e>last && e<8);last=e;
        }
        WXGStretchPose c=WXGStretchPoseMake(none,1,0,44,44,capped);assert(near(c.a*44-44,.6,.002));
        c=WXGStretchPoseMake(none,0,-40,300,36,capped);assert(c.d*36-36<=8 && c.d*36-36>7.9);
    }
    /* FIX80: follow moves the glass by that share of the pull, on top of the
       reach; 0 is the FIX70 pose. */
    {
        const WXGStretchStyle still={.6,1,0,0},moving={.6,1,0,.3};
        WXGStretchPose a=WXGStretchPoseMake(none,10,-4,44,44,still),b=WXGStretchPoseMake(none,10,-4,44,44,moving);
        assert(near(b.tx-a.tx,3,1e-9) && near(b.ty-a.ty,-1.2,1e-9) && a.a==b.a && a.b==b.b && a.d==b.d);
        b=WXGStretchPoseMake(none,10,0,200,44,moving);a=WXGStretchPoseMake(none,10,0,200,44,still);assert(near(b.tx-a.tx,3,1e-9));
        /* Fit still keeps a moving glass in its clip. */
        WXGButtonPressPose p=WXGButtonPress(1,0,-1,0);
        double k=WXGStretchFit(p,0,-16,300,36,18,moving,-160,-24,160,24);
        WXGStretchPose fit=WXGStretchPoseMake(p,0,-16*k,300,36,moving);
        double rx,ry;WXGStretchReach(fit,300,36,18,&rx,&ry);assert(k<1 && fit.ty-ry>=-24-1e-4);
    }
    puts("PASS: press stretch (FIX68/70/73): rubber band, pose deforming in place (far side within 10%) (along +amount*o, across -amount*o/2, symmetric on diagonals), children follow, follow / release springs, dock end stretch keeps the far end; FIX73 exact posed reach, pull limited to what a clipping parent shows; FIX80 non-round glass only along x / y at its share, lengthening eased into the maximum, follow share of the pull.");
    return 0;
}
