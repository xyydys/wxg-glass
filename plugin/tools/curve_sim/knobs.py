#!/usr/bin/env python3
"""FIX114 J: ReferenceAnalysis/FIX114J_调节项.png: what 过渡宽度 / 边缘最大拉伸 /
过渡曲线 do at 边界过渡 1, and 背景饱和度 with a thinner material, through
the plugin's own mesh.  usage: python3 knobs.py <out dir> <busy-screenshot.png>"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render import *

def main():
    out = sys.argv[1]
    Wpt, Hpt = 74, 62; rect = (6, 8, 300, 44)
    W, S = 8.367, 8.671
    bg = scene(Wpt, Hpt, rect[0], rect[1], pre=2.5)
    m = lambda **k: mesh(rect[2], rect[3], 0, W, S, 1, **k)
    rows = [[('边缘最大拉伸 1.5', draw(bg, rect, *m(stretch=1.5))), ('边缘最大拉伸 2.5（默认）', draw(bg, rect, *m())), ('边缘最大拉伸 5', draw(bg, rect, *m(stretch=5)))],
            [('过渡曲线 1.5', draw(bg, rect, *m(power=1.5))), ('过渡曲线 2（默认）', draw(bg, rect, *m())), ('过渡曲线 3.5', draw(bg, rect, *m(power=3.5)))],
            [('过渡宽度 10 pt', draw(bg, rect, *m(width=10))), ('过渡宽度 0（自动，这里 22 pt）', draw(bg, rect, *m())), ('过渡宽度 16 pt + 拉伸 4', draw(bg, rect, *m(width=16, stretch=4)))]]
    if len(sys.argv) > 2:
        busy = photo(sys.argv[2], (195, 550, 480, 840), Wpt, Hpt, (2, 12), pre=1.0)
        V, Fq = m()
        rows.append([('饱和度 1.05 + 白色材质 22%', draw(busy, rect, V, Fq)),
                     ('饱和度 1.6 + 材质 10%', draw(busy, rect, V, Fq, veil=.10, saturation=1.6)),
                     ('饱和度 2.2 + 材质 5% + 亮度 +0.05', draw(busy, rect, V, Fq, veil=.05, saturation=2.2, brightness=.05))])
    font = ImageFont.truetype(FONT, 20)
    tiles = [[(n, to_img(t)) for n, t in r] for r in rows]
    w, h = tiles[0][0][1].size
    S2 = Image.new('RGB', (3*(w+12), len(tiles)*(h+36)), (255, 255, 255)); dr = ImageDraw.Draw(S2)
    for j, r in enumerate(tiles):
        for i, (n, im) in enumerate(r):
            x, y = i*(w+12), j*(h+36)
            S2.paste(im, (x, y+32)); dr.text((x+4, y+4), n, fill=(0, 0, 0), font=font)
    path = os.path.join(out, 'FIX114J_调节项.png'); S2.save(path); print('wrote', path)

if __name__ == '__main__':
    main()
