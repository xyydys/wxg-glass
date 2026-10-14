#!/usr/bin/env python3
"""Plot actual TEST9 C functions; no iOS screenshot or system curve inference."""
import csv,os,pathlib,subprocess,tempfile
os.environ.setdefault('MPLCONFIGDIR','/tmp/wxg-test4-matplotlib')
os.environ.setdefault('XDG_CACHE_HOME','/tmp/wxg-test4-fontcache')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
root=pathlib.Path(__file__).resolve().parents[1]
program='''#include "WXGOptics.h"
#include <stdio.h>
int main(void) {
 puts("depth,offset10,offset20,sharp0,sharp50,mappedDefault,mappedStrong,strength,peak");
 for(int i=0;i<=400;i++) {
  float d=i*.05f,s=i*.01f;
  printf("%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\\n",d,
    WXGOpticalOffset(-d,10,1.15),WXGOpticalOffset(-d,20,1.15),
    WXGBlurSharpWeight(-d,10,0),WXGBlurSharpWeight(-d,10,.5),
    d+WXGOpticalOffset(-d,10,1.15),d+WXGOpticalOffset(-d,10,3),s,WXGOpticalOffset(0,10,s));
 }
}'''
with tempfile.TemporaryDirectory() as tmp:
 c=pathlib.Path(tmp)/'curve.c';exe=pathlib.Path(tmp)/'curve';c.write_text(program)
 subprocess.run(['cc','-std=c11','-O2','-I'+str(root/'Sources'),str(c),'-lm','-o',str(exe)],check=True)
 data=subprocess.check_output([str(exe)],text=True)
(root/'Validation/TEST9_optical_profile.csv').write_text(data)
rows=list(csv.DictReader(data.splitlines()))
def col(key):return [float(r[key]) for r in rows]
plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
fig,axs=plt.subplots(2,2,figsize=(11,7.8),layout='constrained')
fig.suptitle('TEST9 optics: computed from the delivered C functions',fontsize=16,fontweight='bold')
a=axs[0,0];a.plot(col('depth'),col('offset10'),label='Width 10 pt (default)');a.plot(col('depth'),col('offset20'),label='Width 20 pt');a.set(title='Width changes both range and peak',xlabel='Inward distance from edge (pt)',ylabel='Sampling displacement (pt)');a.legend()
a=axs[0,1];a.plot(col('depth'),col('sharp0'),label='Coverage 0% (default)');a.plot(col('depth'),col('sharp50'),label='Coverage 50%');a.set(title='Sharp share in sharp / Gaussian mix',xlabel='Inward distance (pt)',ylabel='Sharp weight',ylim=(-.03,1.03));a.legend()
a=axs[1,0];a.plot(col('strength'),col('peak'));a.axvspan(1.25,2,color='#edb450',alpha=.22,label='Legacy plateau 1.25–2');a.set(title='Peak displacement at width 10 pt',xlabel='Refraction strength',ylabel='Peak displacement (pt)');a.legend()
a=axs[1,1];a.plot(col('depth'),col('mappedDefault'),label='Strength 1.15 (default)');a.plot(col('depth'),col('mappedStrong'),label='Strength 3');a.plot(col('depth'),col('depth'),ls=':',color='gray',label='No displacement');a.set(xlim=(0,10),ylim=(0,11),title='Mapping along the inward normal',xlabel='Output distance (pt)',ylabel='Sampled distance (pt)');a.legend()
for a in axs.flat:a.grid(alpha=.2)
fig.text(.5,-.018,'Numerical profiles only — not iOS 26 measurements or a device rendering.',ha='center',fontsize=10)
for ext in ['svg','png']:fig.savefig(root/f'Validation/TEST9_optical_profile.{ext}',dpi=160,bbox_inches='tight')
print('Wrote CSV, SVG and PNG from the actual optical functions.')
