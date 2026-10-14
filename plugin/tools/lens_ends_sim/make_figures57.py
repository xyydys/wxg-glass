#!/usr/bin/env python3
"""FIX57: draw the lens-end figures in ReferenceAnalysis/ (FIX47 vs FIX57).
Needs numpy, scipy, Pillow and Noto Sans CJK (wxgsim.FONT). Geometry is the
user's FIX54 screenshots; optics the FIX49 values (lens refraction 4.21, band
20.26 at the ends, top/bottom ratio 0.305, inset 0.131); light appearance
close to the user's FIX47 screenshot. Usage: python3 make_figures57.py"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
import wxgsim as W
import sim57 as S
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'ReferenceAnalysis') + os.sep
F = lambda s: ImageFont.truetype(W.FONT, s)
BG = (245, 245, 247)

def ease(u): return .5 - .5 * math.cos(math.pi * min(max(u, 0), 1))
def path(t):                                   # lens centre: to the last tab (endWrap 4) and back
    if t < .9: return 300 + 44.83 * ease(t / .9)
    if t < 1.3: return 344.83
    return 344.83 - 44.83 * ease((t - 1.3) / .9)
def enhance(img, k=2.5, zoom=1):
    im = Image.fromarray(img) if isinstance(img, np.ndarray) else img
    im = ImageEnhance.Contrast(im).enhance(k)
    return im.resize((im.width * zoom, im.height * zoom), Image.LANCZOS) if zoom != 1 else im
def titled(img, text, size=24, pad=40):
    out = Image.new('RGB', (img.width, img.height + pad), BG); out.paste(img, (0, pad))
    ImageDraw.Draw(out).text((10, (pad - size) // 2 - 2), text, font=F(size), fill=(20, 20, 20)); return out
def grid(rows, gap=10):
    w = max(sum(c.width for c in r) + gap * (len(r) - 1) for r in rows)
    h = sum(max(c.height for c in r) for r in rows) + gap * (len(rows) - 1)
    out = Image.new('RGB', (w, h), BG); y = 0
    for r in rows:
        x = 0
        for c in r: out.paste(c, (x, y)); x += c.width + gap
        y += max(c.height for c in r) + gap
    return out
def header(width, lines, size=28):
    im = Image.new('RGB', (width, (size + 10) * len(lines) + 18), BG); d = ImageDraw.Draw(im)
    for i, t in enumerate(lines): d.text((10, 8 + i * (size + 10)), t, font=F(size if i == 0 else size - 6), fill=(0, 0, 0) if i == 0 else (70, 70, 70))
    return im
def frames(P, cx):
    reach = S.reach_pair(P, P.lens_rect(cx))
    return S.render(P, cx), S.render(P, cx, conv=reach), reach[1]
def pair(P, cx, label, k=2.5, zoom=1):
    a, b, r = frames(P, cx)
    state = '和 FIX47 相同' if r <= 0 else ('右端已放松到上下边宽度' if r > .999 else '右端放松 %.0f%%' % (r * 100))
    return [titled(enhance(a, k, zoom), 'FIX47 · ' + label), titled(enhance(b, k, zoom), 'FIX57 · ' + state)]

def dark_page(P):
    P.page = np.array([70., 70., 70.]); P.tint_a = .8; P.rim_a = .5; P.lens_rim_a = .6
    return P

def main():
    # 0. the middle of the dock and screenshots 1-2: FIX57 is FIX47, pixel for pixel
    P = S.light_params(); P.view = (250.0, 797.0, 414.0, 890.0)
    for cx in (300.0, 321.17, 329.67):
        a, b, _ = frames(P, cx); assert np.array_equal(a, b), cx
    # 1. side by side, light appearance like the screenshot
    g = grid([pair(P, 300.0, '透镜在中段'), pair(P, 321.17, '截图 1 的位置'), pair(P, 337.67, '截图 4 的位置'),
              pair(P, 341.0, '透镜右沿刚到底栏末端'), pair(P, 344.83, '停在“我”（外包 4 pt）')])
    grid([[header(g.width, ['左：FIX47　右：FIX57（按截图尺寸模拟，透镜折射 4.21，对比度加强）',
                            '透镜右沿离底栏末端 10 pt 时开始放松，越过末端 2 pt 时完成；中段与 FIX47 逐像素相同'])], [g]]).save(OUT + 'FIX57_end_compare.png')
    # 2. the end stop, zoomed: as in the screenshot, and with a dark page for clarity
    rows = []
    for dark in (False, True):
        P = S.light_params(); P.view = (346.0, 800.0, 404.0, 887.0)
        if dark: dark_page(P)
        a, b, _ = frames(P, 344.83)
        k = 3.5 if not dark else 1.0
        rows.append([titled(enhance(a, k, 3), 'FIX47' + (' · 页面调暗' if dark else '')), titled(enhance(b, k, 3), 'FIX57' + (' · 页面调暗' if dark else ''))])
    g = grid(rows)
    grid([[header(g.width, ['停在“我”时透镜右端放大 3 倍',
                            'FIX47：内部底栏一直连到透镜边（截图里的粘连）',
                            'FIX57：内部底栏露出自己的圆头，和透镜边之间留出一圈缝'], 26)], [g]]).save(OUT + 'FIX57_end_zoom.png')
    # 3. slow-motion GIF: to the last tab and back (60 Hz steps, 3x slower)
    P = S.light_params(); P.view = (262.0, 799.0, 414.0, 889.0)
    f, fs = F(22), F(18); dt = 1 / 60; out = []
    for i in range(int(2.2 * 60)):
        t = i * dt; cx = path(t)
        a, b, r = frames(P, cx); a, b = enhance(a), enhance(b)
        canvas = Image.new('RGB', (a.width * 2 + 12, a.height + 64), BG); d = ImageDraw.Draw(canvas)
        d.text((8, 4), 'FIX47', font=f, fill=(0, 0, 0)); d.text((a.width + 20, 4), 'FIX57', font=f, fill=(0, 0, 0))
        canvas.paste(a, (0, 34)); canvas.paste(b, (a.width + 12, 34))
        d.text((8, a.height + 38), '慢放 3 倍 · 折射 4.21 · t=%.2fs · 右端放松 %.0f%%' % (t, r * 100), font=fs, fill=(60, 60, 60))
        out.append(canvas.convert('P', palette=Image.ADAPTIVE, colors=128))
    out[0].save(OUT + 'FIX57_slide_slowmo.gif', save_all=True, append_images=out[1:], duration=50, loop=0, optimize=True)

if __name__ == '__main__':
    main()
