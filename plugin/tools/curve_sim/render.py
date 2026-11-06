#!/usr/bin/env python3
"""FIX114 I: draws a body glass through the plugin's own render-server mesh
(dump_mesh.c -> WXGBuildContourMesh), triangle by triangle like
CAMeshTransform, over a backdrop, so TEST9's curve and 边界过渡 can be
compared on the same picture.  Needs numpy, scipy, Pillow.

  python3 render.py out.png            # the comparison sheet
Build dump_mesh first:  cc -O2 dump_mesh.c -lm -o dump_mesh (next to this file)."""
import os, subprocess, sys
import numpy as np
from scipy.ndimage import gaussian_filter, map_coordinates
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PX = 4.0                     # px per pt
DUMP = os.environ.get('WXG_DUMP_MESH', os.path.join(HERE, 'dump_mesh'))
FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'

def mesh(w, h, radius, edge, refr, transition=0.0, stretch=0.0, power=0.0, width=0.0):
    args = [DUMP] + [str(v) for v in (w, h, radius, edge, refr, transition, stretch, power, width)]
    out = subprocess.run(args, capture_output=True, text=True, check=True).stdout.split('\n')
    n = int(out[0].split()[1]); V = np.array([[float(x) for x in l.split()] for l in out[1:1+n]])
    m = int(out[1+n].split()[1]); Fq = np.array([[int(x) for x in l.split()] for l in out[2+n:2+n+m]])
    return V, Fq

def rasterize(V, Fq, w, h):
    """Per pixel of the layer (w x h pt at PX): the source point (layer pt), NaN where no face."""
    W, H = int(round(w*PX)), int(round(h*PX))
    sx = np.full((H, W), np.nan); sy = np.full((H, W), np.nan)
    to = V[:, 2:4]*[w*PX, h*PX]; fr = V[:, 0:2]*[w, h]
    tris = np.concatenate([Fq[:, [0, 1, 2]], Fq[:, [0, 2, 3]]])
    for a, b, c in tris:
        A, B, C = to[a], to[b], to[c]
        area = (B[0]-A[0])*(C[1]-A[1])-(C[0]-A[0])*(B[1]-A[1])
        if abs(area) < 1e-9: continue
        x0, x1 = int(max(0, np.floor(min(A[0], B[0], C[0])))), int(min(W-1, np.ceil(max(A[0], B[0], C[0]))))
        y0, y1 = int(max(0, np.floor(min(A[1], B[1], C[1])))), int(min(H-1, np.ceil(max(A[1], B[1], C[1]))))
        if x1 < x0 or y1 < y0: continue
        ys, xs = np.mgrid[y0:y1+1, x0:x1+1]; px = xs+.5; py = ys+.5
        l1 = ((B[0]-px)*(C[1]-py)-(C[0]-px)*(B[1]-py))/area
        l2 = ((C[0]-px)*(A[1]-py)-(A[0]-px)*(C[1]-py))/area
        l3 = 1-l1-l2
        ins = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
        if not ins.any(): continue
        sx[ys[ins], xs[ins]] = (l1*fr[a, 0]+l2*fr[b, 0]+l3*fr[c, 0])[ins]
        sy[ys[ins], xs[ins]] = (l1*fr[a, 1]+l2*fr[b, 1]+l3*fr[c, 1])[ins]
    return sx, sy

def capsule_distance(x, y, w, h):
    r = min(w, h)*.5
    qx = np.abs(x)-(w*.5-r); qy = np.abs(y)-(h*.5-r)
    ox = np.maximum(0, qx); oy = np.maximum(0, qy)
    return np.sqrt(ox*ox+oy*oy)+np.minimum(np.maximum(qx, qy), 0)-r

def photo(path, box, Wpt, Hpt, at, pre=0.0):
    """A crop of a 3x screenshot (pixels `box`) placed at `at` (pt) on a light grey page, optionally pre-blurred (pt)."""
    im = Image.open(path).convert('RGB').crop(box)
    im = im.resize((int(im.width*PX/3), int(im.height*PX/3)), Image.LANCZOS)
    page = Image.new('RGB', (int(Wpt*PX), int(Hpt*PX)), (238, 238, 238)); page.paste(im, (int(at[0]*PX), int(at[1]*PX)))
    a = np.asarray(page).astype(float)/255
    return np.stack([gaussian_filter(a[..., c], pre*PX) for c in range(3)], -1) if pre > 0 else a

def scene(Wpt, Hpt, rim_x, top_y, pre=0.0):
    """White page; a photo whose top-left (dark hair) lies under the capsule's left end, like the screenshots."""
    ys, xs = np.mgrid[0:int(Hpt*PX), 0:int(Wpt*PX)]
    x = (xs+.5)/PX; y = (ys+.5)/PX
    img = np.ones(x.shape+(3,))*.985
    px0, py0 = rim_x+3.2, top_y+13.0
    photo = (x > px0) & (x < px0+125) & (y > py0) & (y < py0+125)
    img[photo] = [.90, .88, .86]
    ell = lambda cx, cy, rx, ry: ((x-cx)/rx)**2+((y-cy)/ry)**2
    img[photo & (ell(px0+30, py0+30, 14, 20) < 1)] = [.86, .72, .62]
    img[photo & ((ell(px0+11, py0+16, 7.5, 22) < 1) | (ell(px0+24, py0+2, 18, 7) < 1))] = [.16, .15, .15]
    for k in range(8): img[photo & (ell(px0+38, py0+48+k*5, 1.4, 1.4) < 1)] = [.97, .96, .95]
    if pre > 0: img = np.stack([gaussian_filter(img[..., c], pre*PX) for c in range(3)], -1)
    return img

def tone(img, saturation=1.05, brightness=0.0):
    """FIX114 J: the backdrop's saturation (Rec.709 luma) and brightness, as the plugin's colour filters."""
    luma = (img*np.array([.2126, .7152, .0722])).sum(-1, keepdims=True)
    return np.clip(luma+(img-luma)*saturation+brightness, 0, 1)

def draw(bg, rect, V, Fq, blur=.9, veil=.22, rim=.75, saturation=1.05, brightness=0.0, veil_rgb=(1, 1, 1)):
    X, Y, w, h = rect
    sx, sy = rasterize(V, Fq, w, h)
    soft = tone(np.stack([gaussian_filter(bg[..., c], blur*PX) for c in range(3)], -1), saturation, brightness)
    H, W = sx.shape
    gx = np.where(np.isnan(sx), 0, sx)+X; gy = np.where(np.isnan(sy), 0, sy)+Y
    face = np.stack([map_coordinates(soft[..., c], [gy*PX-.5, gx*PX-.5], order=1, mode='nearest') for c in range(3)], -1)
    ys, xs = np.mgrid[0:H, 0:W]; x = (xs+.5)/PX-w*.5; y = (ys+.5)/PX-h*.5
    d = capsule_distance(x, y, w, h)
    inside = (np.clip(.5-d*PX, 0, 1)*(~np.isnan(sx)))[..., None]
    face = face*(1-veil)+veil*np.array(veil_rgb)
    rimw = (np.clip(1+d/1.2, 0, 1)**2*rim)[..., None]
    face = face*(1-rimw)+rimw
    out = bg.copy()
    y0, x0 = int(round(Y*PX)), int(round(X*PX))
    hh, ww = min(H, out.shape[0]-y0), min(W, out.shape[1]-x0)
    region = out[y0:y0+hh, x0:x0+ww]
    out[y0:y0+hh, x0:x0+ww] = region*(1-inside[:hh, :ww])+face[:hh, :ww]*inside[:hh, :ww]
    return np.clip(out, 0, 1)

def to_img(a): return Image.fromarray((a*255+.5).astype(np.uint8))

def sheet(tiles, cols, path, label=22):
    font = ImageFont.truetype(FONT, label)
    ims = [to_img(t) if isinstance(t, np.ndarray) else t for _, t in tiles]
    w, h = ims[0].size
    rows = (len(ims)+cols-1)//cols
    S = Image.new('RGB', (cols*(w+12), rows*(h+label+14)), (255, 255, 255)); dr = ImageDraw.Draw(S)
    for i, (im, (name, _)) in enumerate(zip(ims, tiles)):
        cx, cy = (i % cols)*(w+12), (i//cols)*(h+label+14)
        S.paste(im.resize((w, h)), (cx, cy+label+10)); dr.text((cx+4, cy+2), name, fill=(0, 0, 0), font=font)
    S.save(path)

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'compare.png'
    Wpt, Hpt = 95, 62; rect = (6, 8, 260, 44)
    bg = scene(Wpt, Hpt, rect[0], rect[1])
    tiles = [(f'边界过渡 {t:g}', draw(bg, rect, *mesh(rect[2], rect[3], 0, 8.367, 8.671, t))) for t in (0, .5, .8, 1)]
    sheet(tiles, 2, out)
    print('wrote', out)
