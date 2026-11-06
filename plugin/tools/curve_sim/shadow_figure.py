#!/usr/bin/env python3
"""FIX114 K: ReferenceAnalysis/FIX114K_外阴影.png: the user's iOS 26 screenshot
next to the plugin's drop shadow (shadow_dump, the plugin's own code) drawn on
the same page, and both brightness profiles.
usage: python3 shadow_figure.py <shadow_dump> <out dir> <ios26.jpg>"""
import os, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont
FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
dump, out, ref = sys.argv[1:4]
R = np.asarray(Image.open(ref).convert('RGB')).astype(float)
H, W = R.shape[:2]
cx, cy, r = 125.5, 251.5, 65.0          # the button in the screenshot (3 px / pt)
yy, xx = np.mgrid[0:H, 0:W]
def rrect(x, y, x0, y0, x1, y1, rad):
    qx = np.maximum(np.maximum(x0+rad-x, x-(x1-rad)), 0); qy = np.maximum(np.maximum(y0+rad-y, y-(y1-rad)), 0)
    inside = np.minimum(np.maximum(np.maximum(x0+rad-x, x-(x1-rad)), np.maximum(y0+rad-y, y-(y1-rad))), 0)
    return np.sqrt(qx**2+qy**2)+inside-rad
card = rrect(xx+.5, yy+.5, 24, 360, 470, 467.5, 24) < 0
page = np.where(card, 255., 237.)
with tempfile.TemporaryDirectory() as d:
    pgm = os.path.join(d, 's.pgm')
    pw, ph, m = subprocess.run([dump, '44', '44', '22', '17', '8', '0', '3', pgm], capture_output=True, text=True, check=True).stdout.split()
    A = np.asarray(Image.open(pgm)).astype(float)/65535
m = float(m); S = np.zeros((H, W))
x0, y0 = int(round(cx-(22+m)*3)), int(round(cy-(22+m)*3))
ys, xs = slice(max(0, y0), min(H, y0+A.shape[0])), slice(max(0, x0), min(W, x0+A.shape[1]))
S[ys, xs] = A[ys.start-y0:ys.stop-y0, xs.start-x0:xs.stop-x0]
sim = page*(1-.2*S)
button = np.hypot(xx+.5-cx, yy+.5-cy) <= r
sim[button] = 250
sim = np.repeat(sim[..., None], 3, -1)
sim[:140] = R[:140]; sim[540:] = R[540:]     # the status bar and the label: as the screenshot
font = ImageFont.truetype(FONT, 22)
tiles = [('iOS 26 截图', Image.fromarray(R.astype(np.uint8))), ('插件 · 外阴影默认值（同一张底图）', Image.fromarray(np.clip(sim, 0, 255).astype(np.uint8)))]
# profiles: down / side / up from the button's edge, darkening in %
L = R.mean(-1); D = 1-L/page; Ds = 1-sim.mean(-1)/page
plot = Image.new('RGB', (W, H), 'white'); dr = ImageDraw.Draw(plot)
dr.text((10, 8), '变暗程度（%） vs 离按钮边缘（pt）', fill='black', font=font)
X0, Y0, PW, PH = 50, 60, W-70, H-140
dr.rectangle([X0, Y0, X0+PW, Y0+PH], outline=(180, 180, 180))
cols = {'下': (40, 90, 200), '旁边': (200, 60, 40), '上': (40, 150, 70)}
for name, (dx, dy) in (('下', (0, 1)), ('旁边', (1, 0)), ('上', (0, -1))):
    for src, dash in ((D, False), (Ds, True)):
        pts = []
        for t in range(1, 120):
            x, y = int(cx+dx*(r+t)), int(cy+dy*(r+t))
            if 0 <= x < W and 0 <= y < H and not (abs(y-360) < 4 or abs(y-467) < 4):
                pts.append((X0+PW*(t/3)/40, Y0+PH*(1-src[y, x]/.12)))
        for i in range(1, len(pts)):
            if dash and i % 2: continue
            dr.line([pts[i-1], pts[i]], fill=cols[name], width=3 if not dash else 2)
for k, (name, c) in enumerate(cols.items()): dr.text((X0+PW-150, Y0+10+k*30), name, fill=c, font=font)
dr.text((X0, Y0+PH+10), '实线 = iOS 26 截图    虚线 = 插件', fill='black', font=font)
for v in (0, 3, 6, 9, 12): dr.text((10, Y0+PH*(1-v/12)-12), str(v), fill='gray', font=font)
for v in (0, 10, 20, 30, 40): dr.text((X0+PW*v/40-8, Y0+PH+40), str(v), fill='gray', font=font)
tiles.append(('', plot))
S2 = Image.new('RGB', (len(tiles)*(W+16), H+40), 'white'); d2 = ImageDraw.Draw(S2)
for i, (n, im) in enumerate(tiles):
    S2.paste(im, (i*(W+16), 38)); d2.text((i*(W+16)+4, 4), n, fill='black', font=font)
path = os.path.join(out, 'FIX114K_外阴影.png'); S2.save(path); print('wrote', path)
