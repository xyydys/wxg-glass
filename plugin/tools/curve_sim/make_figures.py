#!/usr/bin/env python3
"""FIX114 I: ReferenceAnalysis/FIX114I_边界过渡.png: TEST9 (边界过渡 0) against
边界过渡 0.5 / 0.8 / 1 on a picture like the user's screenshots and on a busy
one, drawn through the plugin's own mesh (dump_mesh.c).
usage: python3 make_figures.py <out dir> [your-screenshot.jpg ios26-screenshot.jpg busy-screenshot.png]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render import *

def crop_ref(path, top, rim, hpx, Wpt, Hpt, rect):
    im = Image.open(path).convert('RGB'); s = rect[3]*PX/hpx
    im2 = im.resize((int(im.width*s), int(im.height*s)), Image.LANCZOS)
    ox = int(rim*s-rect[0]*PX); oy = int(top*s-rect[1]*PX)
    tile = Image.new('RGB', (int(Wpt*PX), int(Hpt*PX)), (255, 255, 255))   # outside the screenshot: white
    tile.paste(im2, (-ox, -oy))
    return tile

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    Wpt, Hpt = 74, 62; rect = (6, 8, 300, 44)            # the pinned-message capsule: 44 pt high
    W, S = 8.367, 8.671                                  # the user's 其余玻璃 (FIX114 H export)
    steps = (0, .5, .8, 1)
    name = lambda t: '原版（边界过渡 0）' if t == 0 else f'边界过渡 {t:g}'
    rows = []
    if len(sys.argv) > 3:
        rows.append([('你的截图（原版）', crop_ref(sys.argv[2], 30, 25, 122, Wpt, Hpt, rect)),
                     ('iOS 26 截图', crop_ref(sys.argv[3], 33, 27, 126, Wpt, Hpt, rect))])
    bg = scene(Wpt, Hpt, rect[0], rect[1], pre=2.5)
    rows.append([('模拟 · '+name(t), draw(bg, rect, *mesh(rect[2], rect[3], 0, W, S, t))) for t in steps])
    if len(sys.argv) > 4:
        busy = photo(sys.argv[4], (195, 550, 480, 840), Wpt, Hpt, (2, 12), pre=1.0)
        rows.append([('细节多的背景 · '+name(t), draw(busy, rect, *mesh(rect[2], rect[3], 0, W, S, t))) for t in steps])
    font = ImageFont.truetype(FONT, 20)
    tiles = [[(n, to_img(t) if isinstance(t, np.ndarray) else t) for n, t in r] for r in rows]
    w, h = tiles[-1][0][1].size
    cols = max(len(r) for r in tiles)
    S2 = Image.new('RGB', (cols*(w+12), len(tiles)*(h+36)), (255, 255, 255)); dr = ImageDraw.Draw(S2)
    for j, r in enumerate(tiles):
        for i, (n, im) in enumerate(r):
            x, y = i*(w+12), j*(h+36)
            S2.paste(im.resize((w, h)), (x, y+32)); dr.text((x+4, y+4), n, fill=(0, 0, 0), font=font)
    path = os.path.join(out, 'FIX114I_边界过渡.png'); S2.save(path)
    print('wrote', path)

if __name__ == '__main__':
    main()
