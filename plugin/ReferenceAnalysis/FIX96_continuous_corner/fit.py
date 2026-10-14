#!/usr/bin/env python3
"""FIX96: fit WXGContinuousDeviation (Sources/WXGOptics.h) to the measured
continuous-corner deviation (dock_end_deviation.csv): a K-term sine series over
-24..90 degrees, zero at both ends. The lens of the same screenshot (aspect
1.26) matched the dock's curve (aspect 5.3) to 0.2% R over -16..28 degrees.
Usage: python3 fit.py [K=5]"""
import math, os, sys
import numpy as np
here=os.path.dirname(os.path.abspath(__file__))
d=np.loadtxt(os.path.join(here,'dock_end_deviation.csv'),delimiter=',',comments='#',skiprows=4)
K=int(sys.argv[1]) if len(sys.argv)>1 else 5
phi,y=d[:,0],d[:,1];s=(phi>=-24)&(phi<=90);phi,y=phi[s],y[s]
t=(phi+24)/114
A=np.stack([np.sin(k*math.pi*t) for k in range(1,K+1)],1)
c,*_=np.linalg.lstsq(A,y,rcond=None)
print('coefficients',' '.join('%.6f'%v for v in c),' rms %.5f R'%np.sqrt(np.mean((y-A@c)**2)))
