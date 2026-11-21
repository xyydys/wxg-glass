"""Compile the production capture margin with the native mesh source mapping."""
from pathlib import Path
import os
import subprocess
import tempfile

sources = Path(__file__).resolve().parents[1] / "Sources"
host = (sources / "WXGGlassView.m").read_text()
start = host.index("static inline float WXGKyantOpticalCaptureMargin(")
margin_function = host[start:host.index("\n}", start) + 2]
sweep = r"""
#include <assert.h>
#include <stdio.h>
static float check(float width,float height,float amount,float band,float dispersion,
                   float zoom,float pinch,int end,unsigned *rays) {
    float halfBar=32, oldPad=fminf(40,2*ceilf((halfBar*(1-1/zoom)+halfBar*pinch/zoom+2)*.5f));
    float pad=oldPad+WXGKyantOpticalCaptureMargin(band,amount,dispersion,fminf(width,height));
    WXGMeshOptics o={0};
    o.width=width+2*pad; o.height=height+2*pad; o.padX=o.padY=pad;
    o.kyantMode=o.shrinkPress=1; o.zoomAfter=zoom; o.shrinkPinch=pinch;
    o.kyantAmount=amount; o.kyantHeight=band; o.dispersion=dispersion;
    o.sbLeft=pad-(end?3:120); o.sbRight=o.sbLeft+360;
    o.sbTop=pad+(height-2*halfBar)*.5f; o.sbBottom=o.sbTop+2*halfBar;
    wxg_kf2_t half={width*.5f,height*.5f};
    float worst=0;
    for(float y=0;y<height;y+=.75f)for(float x=0;x<width;x+=.75f) {
        if(WXGKyantSdRoundedRect((wxg_kf2_t){x-half.x,y-half.y},half,half.y)>0) continue;
        for(int k=-1;k<=1;k+=2) {
            float sx,sy; o.kyantChannel=k;
            WXGMeshSource(o,pad+x,pad+y,&sx,&sy);
            worst=fmaxf(worst,fmaxf(fmaxf(-sx,-sy),fmaxf(sx-o.width,sy-o.height)));
            (*rays)++;
        }
    }
    return worst;
}
int main(void) {
    assert(WXGKyantOpticalCaptureMargin(0,50,5,42)==0);
    assert(WXGKyantOpticalCaptureMargin(40,0,5,42)==0);
    assert(WXGKyantOpticalCaptureMargin(18,26,2.4f,70)==40);
    assert(WXGKyantOpticalCaptureMargin(40,50,0,42)<WXGKyantOpticalCaptureMargin(40,50,1,42));
    unsigned rays=0;
    float worst=check(120,70,26,18,2.4f,1.16f,.25f,0,&rays);
    float splits[]={0,.5f,1,2.4f,5};
    for(int end=0;end<2;end++)for(int size=0;size<4;size++)for(int d=0;d<5;d++)
        for(int z=0;z<3;z++)for(int p=0;p<3;p++)
            worst=fmaxf(worst,check(90+size*20,42+size*14,50,40,splits[d],1+z*.1f,p*.15f,end,&rays));
    printf("Kyant capture margins: %u native rays, worst boundary overrun %.5f pt.\n",rays,worst);
    assert(worst<.001f);
}
"""
with tempfile.TemporaryDirectory() as temp:
    executable = Path(temp) / "capture-margin"
    subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-O2", "-I", str(sources),
                    "-x", "c", "-", "-lm", "-o", str(executable)], check=True,
                   input='#include "WXGMeshRefraction.h"\n' + margin_function + sweep, text=True)
    subprocess.run([str(executable)], check=True)
