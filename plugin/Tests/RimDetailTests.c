#include "../Sources/WXGRimDetail.h"
#include <assert.h>
#include <stdio.h>


int main(void) {
    /* FIX79: stepped side fades. The opacity stack gives exactly
       edge + (1 - edge) q / N on step q of either side and 1 in the middle;
       the darkening stack darkens step q by exactly 1 - that level and leaves
       the middle alone; steps are at most 0.1 pt. */
    {
        const double ws[3]={1,.6,1.4},outs[4]={.3,0,.5,1.2},ins[4]={.3,.4,0,.9},edges[3]={0,.35,.8};
        for(int a=0;a<3;a++)for(int f=0;f<4;f++)for(int e=0;e<3;e++) {
            double w=ws[a],o=outs[f],in=ins[f],edge=edges[e];
            WXGRimBands alpha=WXGRimAlphaBands(w,o,in,edge),dim=WXGRimDimBands(w,o,in,edge);
            double fo=o,fi=in;WXGRimFitFades(w,&fo,&fi);
            assert(fo+fi<=w+1e-9);
            int n=WXGRimSteps(fo,fi);
            assert(n<=WXG_RIM_MAX_STEPS && (n==0 || fmax(fo,fi)/n<=.1+1e-9 || n==WXG_RIM_MAX_STEPS));
            for(int k=0;k<alpha.count;k++)assert(alpha.alpha[k]>=-1e-12 && alpha.alpha[k]<=1+1e-12 && alpha.width[k]>-1e-9);
            for(int k=0;k<dim.count;k++)assert(dim.alpha[k]>=-1e-12 && dim.alpha[k]<=1+1e-12);
            for(int i=0;i<200;i++) {
                double t=(i+.5)/200*w,expect=1;
                if(n>0) {
                    if(fo>0 && t<fo){int q=(int)(t/(fo/n));if(q>n-1)q=n-1;expect=WXGRimStepLevel(edge,q,n);}
                    if(fi>0 && t>w-fi){int q=(int)((w-t)/(fi/n));if(q>n-1)q=n-1;expect=WXGRimStepLevel(edge,q,n);}
                }
                /* skip samples within a hair of a step boundary */
                int near_edge=0;
                for(int k=0;k<alpha.count;k++)if(fabs(t-alpha.inset[k])<1e-6 || fabs(t-alpha.inset[k]-alpha.width[k])<1e-6)near_edge=1;
                if(near_edge)continue;
                assert(fabs(WXGRimBandsCover(alpha,t)-expect)<1e-9);
                assert(fabs((1-WXGRimBandsCover(dim,t))-expect)<1e-9);
            }
        }
        /* No fade (or edge 1): one full band, nothing darkened. */
        WXGRimBands plain=WXGRimAlphaBands(1,0,0,.3);assert(plain.count==1 && plain.alpha[0]==1 && plain.width[0]==1);
        assert(WXGRimDimBands(1,.3,.3,1).count==0 && WXGRimAlphaBands(1,.3,.3,1).count==1);
        /* 0.1 pt steps: a 0.3 pt fade is three steps. */
        assert(WXGRimSteps(.3,.2)==3 && WXGRimSteps(.04,0)==0 && WXGRimSteps(5,5)==WXG_RIM_MAX_STEPS);
        assert(!WXGRimStepped(1,0,0,.3) && !WXGRimStepped(1,.3,.3,1) && WXGRimStepped(1,.3,0,.3) && !WXGRimStepped(0,.3,.3,.3));
    }
    /* FIX76: the sampled colour. Neutral parameters are the identity; the
       defaults make a colour brighter, lighter and more saturated than the
       background; brightness keeps the classic meaning (<1 darkens, >1 to white). */
    {
        WXGRimMatrix id=WXGRimSampleMatrix(1,1,1,0,1);
        for(int r=0;r<4;r++)for(int k=0;k<5;k++)assert(fabs(id.m[r*5+k]-((r==k)?1:0))<1e-6);
        WXGRimMatrix m=WXGRimSampleMatrix(1.8,1,1.35,.08,1);
        const double cases[3][3]={{.31,.33,.41},{.12,.12,.12},{.80,.55,.40}};
        for(int c=0;c<3;c++) {
            double out[3];WXGRimApplyMatrix(m,cases[c],out);
            double lin=.2126*cases[c][0]+.7152*cases[c][1]+.0722*cases[c][2],lout=.2126*out[0]+.7152*out[1]+.0722*out[2];
            assert(lout>lin);
            double cin=fmax(fmax(cases[c][0],cases[c][1]),cases[c][2])-fmin(fmin(cases[c][0],cases[c][1]),cases[c][2]);
            double cout=fmax(fmax(out[0],out[1]),out[2])-fmin(fmin(out[0],out[1]),out[2]);
            assert(cout>=cin-1e-9);
        }
        double grey[3]={.5,.5,.5},o[3];
        WXGRimApplyMatrix(WXGRimSampleMatrix(2,1,1,0,.5),grey,o);assert(fabs(o[0]-.25)<1e-6);
        WXGRimApplyMatrix(WXGRimSampleMatrix(2,1,1,0,2),grey,o);assert(fabs(o[0]-1)<1e-6);
        WXGRimApplyMatrix(WXGRimSampleMatrix(1,2,1,0,1),grey,o);assert(fabs(o[0]-.5)<1e-6);   /* contrast pivots on mid grey */
        assert(WXGRimSampleMatrix(1.8,1.2,1.3,.1,1.4).m[18]==1.f);
    }
    puts("PASS: rim details (FIX79): stepped outer / inner side fades (opacity or darkening) exact per 0.1 pt step, middle untouched; sampled colour matrix brighter / lighter / more saturated, classic brightness, alpha kept.");
    return 0;
}
