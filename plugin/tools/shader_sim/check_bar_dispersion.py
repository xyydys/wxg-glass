#!/usr/bin/env python3
"""FIX97: check the colour split of the bar seen through the dock's lens on
the EMBEDDED shader (the CPU simulator, tools/shader_sim).
Usage: python3 tools/shader_sim/check_bar_dispersion.py
Needs clang++, numpy and Pillow. For each lens position (first tab, between,
on a tab, last tab), over a black page (dark mode) and a white one with a
light veil (light mode), it renders the split off (FIX96) and at the
defaults (lensBarDispersion 0.6 pt, lensBarDispersionNearRim 0.35) and checks:
  - not pressed: identical to off (the split scales with the press);
  - away from the bar's edges seen in the lens: unchanged (within 2/255);
  - near them: coloured (red / blue apart by at least 0.05, at most 0.6: a
    1 px fringe on a hard edge already reaches ~0.45), and every channel
    keeps its light (a split, not a tint): its mean over the lens moves by
    less than 0.004; and each channel stays within what the split-off image
    has within 4 pt, to 0.06 (a split only moves colours; Core Animation lays the lens
    pass over the page with one alpha, and without the page added back a
    white page showed red / blue / yellow bands 0.8 below that);
  - no separate lines or bands: down the middle of the slots (lens on a tab)
    and across the bar's end (lens on the first tab) the brightness has no
    more peaks or dips than with the split off (FIX97's first try, three samples,
    drew a red, a green and a blue line)."""
import atexit, os, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
tmp = tempfile.mkdtemp()
atexit.register(shutil.rmtree, tmp, True)
def params(name, **kv):
    path = os.path.join(tmp, name + '.txt')
    with open(path, 'w') as f:
        for k, v in kv.items(): f.write('%s %s\n' % (k, v))
    return path
cases = []
MODES = {'': {}, 'L': {'page': 1, 'tint': .9}}   # dark: black page; light: white page, light veil
for mode, extra in MODES.items():
    for a in (0, 1.5, 2, 3):
        cases.append(params(mode + 'off_%g' % a, anchor=a, margin=0, barDisp=0, barDispRim=0, **extra))
        cases.append(params(mode + 'on_%g' % a, anchor=a, margin=0, barDisp=.6, barDispRim=.35, **extra))
cases.append(params('off_rest', anchor=2, margin=0, press=0, barDisp=0, barDispRim=0))
cases.append(params('on_rest', anchor=2, margin=0, press=0, barDisp=.6, barDispRim=.35))
r = subprocess.run([sys.executable, os.path.join(here, 'build.py'), tmp] + cases, capture_output=True, text=True)
if r.returncode:
    print(r.stdout + r.stderr); sys.exit(1)
lens = {}
for line in r.stdout.splitlines():
    w = line.split()
    if len(w) >= 7 and w[1] == 'lens':   # "<name> lens W x H at X,Y ..."
        x, y = w[6].split(',')
        lens[w[0]] = (float(w[2]), float(w[4]), float(x), float(y))
def img(name): return np.asarray(Image.open(os.path.join(tmp, name + '.png')).convert('RGB'), dtype=np.float64) / 255.
failures = 0
def check(ok, msg):
    global failures
    if not ok:
        failures += 1; print('FAIL', msg)
S = 3
def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out
def localrange(a, r, f):   # min / max over a (2r+1) square, separable
    o = a.copy()
    for k in range(-r, r + 1): o = f(o, np.roll(a, k, 0))
    p = o.copy()
    for k in range(-r, r + 1): p = f(p, np.roll(o, k, 1))
    return p
check(np.array_equal(img('off_rest'), img('on_rest')), 'not pressed: identical to off')
for mode, a in [(m, a) for m in MODES for a in (0, 1.5, 2, 3)]:
    off, on = img(mode + 'off_%g' % a), img(mode + 'on_%g' % a)
    lw, lh, lx, ly = lens[mode + 'on_%g' % a]
    where = '%s anchor %g' % ('light' if mode else 'dark', a)
    H, W, _ = off.shape
    yy, xx = np.mgrid[0:H, 0:W]
    # Inside the lens, 2 pt in from its rim (the CA rim line is the sim's own).
    inner = ((xx + .5) / S > lx + 2) & ((xx + .5) / S < lx + lw - 2) & ((yy + .5) / S > ly + 2) & ((yy + .5) / S < ly + lh - 2)
    inner &= np.hypot(((xx + .5) / S - (lx + lw / 2)) / (lw / 2 - 2), ((yy + .5) / S - (ly + lh / 2)) / (lh / 2 - 2)) < 1.25
    gx = np.abs(np.diff(off, axis=1, append=off[:, -1:])).max(2)
    gy = np.abs(np.diff(off, axis=0, append=off[-1:])).max(2)
    edges = dilate((gx > 2 / 255.) | (gy > 2 / 255.), 14)
    away = inner & ~edges
    d = np.abs(on - off).max(2)
    check(d[away].max() <= 2 / 255. + 1e-9, '%s: changed away from the edges (%.3f)' % (where, d[away].max()))
    split = np.abs((on[..., 0] - on[..., 2]) - (off[..., 0] - off[..., 2]))
    check(split[inner].max() >= .05, '%s: no colour at the edges (%.3f)' % (where, split[inner].max()))
    check(split[inner].max() <= .6, '%s: too strong (%.3f)' % (where, split[inner].max()))
    for c in range(3):
        m = (on[..., c] - off[..., c])[inner].mean()
        check(abs(m) < .004, '%s: channel %d tinted (mean %.4f)' % (where, c, m))
    below = (localrange(off, 12, np.minimum) - on).max(2)[inner].max()
    above = (on - localrange(off, 12, np.maximum)).max(2)[inner].max()
    check(below <= .06 and above <= .06, '%s: outside the local range by %.3f / %.3f' % (where, below, above))
    print('%s: max red/blue split %.3f, outside the local range %.3f / %.3f, unchanged away from edges (max %.4f), channel means %s' %
          (where, split[inner].max(), below, above, d[away].max(), ' '.join('%+.4f' % (on[..., c] - off[..., c])[inner].mean() for c in range(3))))
# One fringe: profiles across the edges; peaks with a prominence of 0.03
# (above the lowest value within 4 px on both sides).
def peaks(prof):
    n = 0
    for i in range(1, len(prof) - 1):
        if prof[i] > prof[i - 1] and prof[i] >= prof[i + 1]:
            if prof[i] - max(prof[max(0, i - 4):i].min(), prof[i + 1:i + 5].min()) > .03: n += 1
    return n
def lum(im, ys, xs): return im[ys, xs].sum(-1) / 3.
for mode, name, horizontal in [(m, n, h) for m in MODES for n, h in (('2', False), ('0', True))]:
    on, off = img(mode + 'on_' + name), img(mode + 'off_' + name)
    lw, lh, lx, ly = lens[mode + 'on_' + name]
    if horizontal:   # across the bar's left end, at the lens' middle height
        row = int((ly + lh / 2) * S)
        xs = np.arange(int((lx + 1.5) * S), int((lx + lw * .45) * S))
        segs = [(np.full_like(xs, row + k), xs) for k in (-2, 0, 2)]
    else:            # down the middle column, top slot and bottom slot
        col = int((lx + lw / 2) * S)
        top = np.arange(int((ly + 1.5) * S), int((ly + lh * .35) * S))
        bot = np.arange(int((ly + lh * .65) * S), int((ly + lh - 1.5) * S))
        segs = [(top, np.full_like(top, col)), (bot, np.full_like(bot, col))]
    for ys, xs in segs:
        for sign, what in ((1, 'peaks'), (-1, 'dips')):
            po, pn = peaks(sign * lum(off, ys, xs)), peaks(sign * lum(on, ys, xs))
            check(pn <= po, '%s anchor %s: %d brightness %s across the edge, %d with the split off' % ('light' if mode else 'dark', name, pn, what, po))
if failures:
    print('check_bar_dispersion: %d failure(s)' % failures); sys.exit(1)
print('PASS: bar colour split in the lens (FIX97): off when not pressed, unchanged away from the edges, soft coloured fringes, no tint, within the local range over black and white pages, no separate lines.')
