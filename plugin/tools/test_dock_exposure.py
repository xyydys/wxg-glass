#!/usr/bin/env python3
"""Compile the actual host exposure helper against device-trace geometries."""
import pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'Sources/WXGHost.m').read_text()
a=source.index('static WXGRect WXGDockExposure(')
b=source.index('\nstatic CGRect WXGPresentedRect',a)
function=source[a:b]
program='''#include <assert.h>
#include <math.h>
typedef struct { double x,y,w,h; } WXGRect;
'''+function+r'''
static void eq(WXGRect r,double x,double y,double w,double h){
 assert(fabs(r.x-x)<1e-7 && fabs(r.y-y)<1e-7);
 assert(fabs(r.w-w)<1e-7 && fabs(r.h-h)<1e-7);
}
int main(void){
 WXGRect band={0,811.3769,440,146.6231};
 // Actual video-page half-pop trace: primary x=-53.0837,
 // foreground x=227.6667. Only the exposed leading segment is glass.
 eq(WXGDockExposure(band,(WXGRect){-53.0837,0,440,956},
     (WXGRect){227.6667,0,440,956}),0,811.3769,227.6667,146.6231);
 // Primary content may stop at y869, above an 87pt native tab bar.
 // Its horizontal exposure must retain the entire independent dock Y band.
 eq(WXGDockExposure((WXGRect){0,845,440,111},(WXGRect){-53,0,440,869},
     (WXGRect){228,0,440,956}),0,845,228,111);
 eq(WXGDockExposure((WXGRect){0,845,440,111},(WXGRect){-53,0,440,869},
     (WXGRect){228,0,440,869}),0,845,228,111);
 eq(WXGDockExposure((WXGRect){0,845,440,111},(WXGRect){0,0,440,869},
     (WXGRect){440,0,440,869}),0,845,440,111);
 // A vertical movement is outside horizontal navigation masking; do not
 // clip the independent dock vertically or fabricate a horizontal cover.
 eq(WXGDockExposure((WXGRect){0,845,440,111},(WXGRect){0,0,440,869},
     (WXGRect){0,400,440,869}),0,845,440,111);
 // Completed/cancelled native endpoints never leave a rectangular fragment.
 eq(WXGDockExposure(band,(WXGRect){0,0,440,956},
     (WXGRect){440,0,440,956}),0,811.3769,440,146.6231);
 eq(WXGDockExposure(band,(WXGRect){0,0,440,956},
     (WXGRect){0,0,440,956}),0,0,0,0);
 // Mirrored native navigation and cropped primary bounds remain bounded.
 eq(WXGDockExposure(band,(WXGRect){53,0,440,956},
     (WXGRect){-220,0,440,956}),220,811.3769,220,146.6231);
 // A partial-height / small custom foreground does not mask a full dock.
 eq(WXGDockExposure(band,(WXGRect){0,0,440,956},
     (WXGRect){0,0,440,500}),0,811.3769,440,146.6231);
 eq(WXGDockExposure(band,(WXGRect){0,0,440,956},
     (WXGRect){100,0,100,956}),0,811.3769,440,146.6231);
 eq(WXGDockExposure(band,(WXGRect){440,0,440,956},
     (WXGRect){0,0,440,956}),0,0,0,0);
 for(int i=0;i<=1000;i++){
  double fraction=i/1000.0,x=440*fraction;
  WXGRect r=WXGDockExposure(band,(WXGRect){-110*(1-fraction),0,440,956},
      (WXGRect){x,0,440,956});
  assert(r.w>=0 && r.w<=440);
  if(i>0)eq(r,0,811.3769,x,146.6231);
 }
 return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='wxg_dock_exposure_') as tmp:
 c=pathlib.Path(tmp)/'test.c';binary=pathlib.Path(tmp)/'test';c.write_text(program)
 subprocess.run(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror',str(c),'-lm','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
print('Dock exposure: logged half-pop, both endpoints, RTL, content-above-tabbar, vertical/custom foreground, 1001 reversible progress samples PASS')
