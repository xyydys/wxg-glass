#!/usr/bin/env python3
"""FIX58: a schematic preview of the new settings pages (not a device capture).

usage: python3 tools/settings_preview/render_fix58_preview.py [out.png]

Layout numbers follow Sources/WXGSettings.m / WXGOpticalSettings.m exactly
(iPhone XS Max: 414 x 896 pt, safe area 44 / 34, size scale 1, card radius 26):
the glass navigation buttons' metrics (WXGMeasure), the home header and the
two-column golden-ratio grid, the module page's range card, groups and rows.
The glass is drawn schematically: the built-in wallpaper blurred, the default
material veil (white 48 % / #29292B 58 %) and the rim (white .65 / .143,
faded on the bottom-left / top-right diagonals). No refraction is drawn.
Needs numpy, scipy, Pillow and Noto Sans CJK.
"""
import math, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

S = 2                      # pixels per point in the preview
W, H = 414, 896
SAFE_TOP, SAFE_BOTTOM = 44, 34
RADIUS = 26
FONTS = '/usr/share/fonts/opentype/noto/'

def font(size, weight='Regular'):
    return ImageFont.truetype(FONTS + f'NotoSansCJK-{weight}.ttc', int(round(size * S)), index=2)

def clamp(v, a, b):
    return max(a, min(b, v))

def measure(width, mult=1.0):
    s = clamp(width / 440.0, .70, 1.25) * clamp(mult, .85, 1.20)
    return {'scale': s, 'edge': 20 * s, 'gap': max(8, 10 * s), 'button': max(36, 44 * s)}

# ---------------------------------------------------------------- wallpaper
def default_wallpaper(dark):
    """WXGDefaultWallpaper: a vertical gradient and five soft colour fields."""
    w, h = W, H     # generated at the view size in points (scale 1), shown aspect-fill
    y = np.linspace(0, 1, h)[:, None, None]
    if dark:
        top, bottom = np.array([.043, .078, .090]), np.array([.035, .055, .078])
        blobs = [(.20, .16, .62, .13, .48, .52, .80), (.90, .36, .55, .20, .26, .62, .65), (.22, .64, .60, .38, .20, .48, .55),
                 (.82, .80, .55, .12, .42, .32, .65), (.45, .98, .52, .10, .28, .48, .60)]
    else:
        top, bottom = np.array([.925, .945, .975]), np.array([.965, .930, .950])
        blobs = [(.18, .16, .62, .55, .78, 1, .85), (.88, .32, .55, 1, .74, .84, .80), (.24, .62, .60, .70, .95, .82, .75),
                 (.82, .78, .55, 1, .88, .62, .70), (.40, .95, .50, .62, .70, 1, .60)]
    img = np.broadcast_to(top + (bottom - top) * y, (h, w, 3)).copy()
    yy, xx = np.mgrid[0:h, 0:w].astype(float) + .5
    for bx, by, br, r, g, b, a in blobs:
        d = np.hypot(xx - bx * w, yy - by * h) / (br * w)
        alpha = (a * np.clip(1 - d, 0, 1))[..., None]
        img = img * (1 - alpha) + np.array([r, g, b]) * alpha
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    return np.asarray(pil.resize((W * S, H * S), Image.BICUBIC)).astype(float) / 255

# ---------------------------------------------------------------- glass
def rounded_mask(w, h, r):
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return np.asarray(m).astype(float) / 255

def draw_glass(canvas, back, rect, radius, dark, pill=False):
    """Blurred backdrop + veil + diagonal-faded rim, clipped to the shape."""
    x, y, w, h = [v * S for v in rect]
    x0, y0, x1, y1 = int(round(x)), int(round(y)), int(round(x + w)), int(round(y + h))
    if x1 <= x0 or y1 <= y0 or y0 >= canvas.shape[0]:
        return
    r = min(w, h) / 2 if pill else min(radius * S, min(w, h) / 2)
    pad = 12
    # The backdrop around the shape (edge-extended past the screen).
    padded = np.pad(back, ((pad, pad + max(0, y1 - back.shape[0])), (pad, pad), (0, 0)), mode='edge')
    region = padded[y0:y1 + 2 * pad, x0:x1 + 2 * pad]
    region = np.stack([gaussian_filter(region[..., c], 1.5 * S) for c in range(3)], -1)[pad:pad + (y1 - y0), pad:pad + (x1 - x0)]
    veil = np.array([.161, .161, .169]) if dark else np.array([1., 1., 1.])
    alpha = .58 if dark else .48
    face = region * (1 - alpha) + veil * alpha
    mask = rounded_mask(x1 - x0, y1 - y0, int(round(r)))
    # Rim: a thin line along the outline, visible top-left / bottom-right.
    inner = rounded_mask(x1 - x0 - 2, y1 - y0 - 2, max(0, int(round(r)) - 1))
    ring = mask.copy()
    ring[1:-1, 1:-1] -= inner
    ring = np.clip(ring, 0, 1)
    yy, xx = np.mgrid[0:y1 - y0, 0:x1 - x0].astype(float)
    nx, ny = (xx - (x1 - x0) / 2) / ((x1 - x0) / 2), (yy - (y1 - y0) / 2) / ((y1 - y0) / 2)
    norm = np.hypot(nx, ny) + 1e-6
    diag = np.abs(nx + ny) / (norm * math.sqrt(2))
    rim_alpha = ring * (.143 if dark else .65) * np.clip(diag, 0, 1)
    face = face * (1 - rim_alpha[..., None]) + rim_alpha[..., None]
    vis = min(y1, canvas.shape[0]) - y0
    target = canvas[y0:y0 + vis, x0:x1]
    m = mask[:vis, :, None]
    canvas[y0:y0 + vis, x0:x1] = target * (1 - m) + face[:vis] * m

# ---------------------------------------------------------------- drawing helpers
class Page:
    def __init__(self, dark):
        self.dark = dark
        self.back = default_wallpaper(dark)
        self.canvas = self.back.copy()
        self.text = []          # deferred: drawn after all glass
        self.shapes = []
        self.label = (1, 1, 1) if dark else (0, 0, 0)
        self.secondary = (.92, .92, .96, .60) if dark else (.235, .235, .263, .60)

    def glass(self, rect, radius=RADIUS, pill=False):
        draw_glass(self.canvas, self.back, rect, radius, self.dark, pill)

    def write(self, x, y, s, size, weight='Regular', color=None, anchor='la', width=None):
        self.text.append((x, y, s, size, weight, color or self.label, anchor, width))

    def shape(self, fn):
        self.shapes.append(fn)

    def image(self):
        img = Image.fromarray((np.clip(self.canvas, 0, 1) * 255).astype(np.uint8)).convert('RGBA')
        over = Image.new('RGBA', img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(over)
        for fn in self.shapes:
            fn(d)
        for x, y, s, size, weight, color, anchor, width in self.text:
            f = font(size, weight)
            c = tuple(int(round(v * 255)) for v in color[:3]) + (int(round((color[3] if len(color) > 3 else 1) * 255)),)
            if width is not None:
                # shrink to fit (adjustsFontSizeToFitWidth) like the labels
                while f.getlength(s) > width * S and f.size > size * S * .7:
                    f = ImageFont.truetype(FONTS + f'NotoSansCJK-{weight}.ttc', f.size - 1, index=2)
            d.text((x * S, y * S), s, font=f, fill=c, anchor=anchor)
        img = Image.alpha_composite(img, over)
        # status bar
        d = ImageDraw.Draw(img)
        col = (255, 255, 255, 255) if self.dark else (0, 0, 0, 255)
        d.text((54 * S, 24 * S), '9:41', font=font(15, 'Medium'), fill=col, anchor='mm')
        return img

def wrap(text, size, width):
    f = font(size)
    lines, cur = [], ''
    for ch in text:
        if f.getlength(cur + ch) > width * S:
            lines.append(cur); cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    return lines

def rgba(c, a=1):
    return tuple(int(round(v * 255)) for v in c[:3]) + (int(round(a * 255)),)

def chevron(page, cx, cy, h, color):
    def fn(d):
        w = h * .5
        pts = [((cx + w * .5) * S, (cy - h * .5) * S), ((cx - w * .5) * S, cy * S), ((cx + w * .5) * S, (cy + h * .5) * S)]
        d.line(pts, fill=rgba(color), width=int(round(2.0 * S)), joint='curve')
    page.shape(fn)

def palette(page, cx, cy, r, color):
    def fn(d):
        d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], outline=rgba(color), width=int(1.8 * S))
        for a in (200, 250, 300, 350):
            px, py = cx + math.cos(math.radians(a)) * r * .55, cy + math.sin(math.radians(a)) * r * .55
            d.ellipse([(px - 1.6) * S, (py - 1.6) * S, (px + 1.6) * S, (py + 1.6) * S], fill=rgba(color))
    page.shape(fn)

def ui_switch(page, x, y, on=True):
    def fn(d):
        d.rounded_rectangle([x * S, y * S, (x + 51) * S, (y + 31) * S], radius=15.5 * S, fill=(52, 199, 89, 255) if on else (120, 120, 128, 90))
        kx = x + (51 - 29) if on else x + 2
        d.ellipse([kx * S, (y + 2) * S, (kx + 27) * S, (y + 29) * S], fill=(255, 255, 255, 255))
    page.shape(fn)

def ui_slider(page, x, y, w, t):
    def fn(d):
        cy = y + 13
        d.rounded_rectangle([x * S, (cy - 2) * S, (x + w) * S, (cy + 2) * S], radius=2 * S, fill=(120, 120, 128, 80))
        d.rounded_rectangle([x * S, (cy - 2) * S, (x + w * t) * S, (cy + 2) * S], radius=2 * S, fill=(0, 122, 255, 255))
        kx = x + w * t
        d.ellipse([(kx - 14) * S, (cy - 14) * S, (kx + 14) * S, (cy + 14) * S], fill=(255, 255, 255, 255), outline=(0, 0, 0, 30))
    page.shape(fn)

# ---------------------------------------------------------------- top bar
def top_bar(page, title):
    m = measure(W, 1.0)
    if m['button'] > 44:
        m = measure(440, 1.0)
    cy = max(SAFE_TOP + 22, SAFE_TOP + m['button'] * .5)
    left, right, mid = m['edge'], W - m['edge'], W * .5
    b = m['button']
    page.glass((left, cy - b / 2, b, b), pill=True)
    page.glass((right - b, cy - b / 2, b, b), pill=True)
    f = font(17 * m['scale'], 'Medium')
    tw_text = f.getlength(title) / S
    limit = 2 * min(mid - (left + b + m['gap']), (right - (b + m['gap'])) - mid)
    tw = min(max(b, limit), max(b, math.ceil(tw_text + 2 * 14 * m['scale'])))
    page.glass((mid - tw / 2, cy - b / 2, tw, b), pill=True)
    page.write(mid, cy, title, 17 * m['scale'], 'Medium', anchor='mm')
    chevron(page, left + b / 2 - 1, cy, b * .5 * .9, page.label)
    palette(page, right - b / 2, cy, b * .24, page.label)
    return m, cy + b / 2 + 18

# ---------------------------------------------------------------- home
CARDS = [('通用', [('基本设置', '适配开关 · 比例 · 诊断'), ('底栏', '尺寸 · 透镜 · 选中胶囊')]),
         ('玻璃 · 底栏与其余玻璃分别设置', [('折射强度和色散', '强度 · 色散 · 折射宽度'), ('模糊强度与范围', '半径 · 覆盖范围 · 清晰度'),
                                ('材质强度与范围', '底色 · 遮盖 · 边缘减弱'), ('边框与渐隐', '颜色 · 宽度 · 亮度 · 渐隐')]),
         ('个性化', [('壁纸', '深浅色壁纸 · 卡片圆角')])]

def icon_placeholder(page, x, y, kind, color):
    def fn(d):
        c = rgba(color)
        X, Y, s = x * S, y * S, 26 * S
        if kind == 0:   # gear
            d.ellipse([X + s * .2, Y + s * .2, X + s * .8, Y + s * .8], outline=c, width=int(2 * S))
            for a in range(0, 360, 45):
                ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
                d.line([X + s / 2 + ca * s * .3, Y + s / 2 + sa * s * .3, X + s / 2 + ca * s * .46, Y + s / 2 + sa * s * .46], fill=c, width=int(2.4 * S))
        elif kind == 1:  # dock
            d.rounded_rectangle([X + s * .08, Y + s * .15, X + s * .92, Y + s * .85], radius=s * .12, outline=c, width=int(2 * S))
            d.rounded_rectangle([X + s * .2, Y + s * .6, X + s * .8, Y + s * .75], radius=s * .07, fill=c)
        elif kind == 2:  # drop
            d.polygon([(X + s * .5, Y + s * .08), (X + s * .25, Y + s * .55), (X + s * .75, Y + s * .55)], outline=c)
            d.arc([X + s * .22, Y + s * .35, X + s * .78, Y + s * .9], 0, 180, fill=c, width=int(2 * S))
            d.line([X + s * .5, Y + s * .08, X + s * .23, Y + s * .58], fill=c, width=int(2 * S))
            d.line([X + s * .5, Y + s * .08, X + s * .77, Y + s * .58], fill=c, width=int(2 * S))
        elif kind == 3:  # blur
            for k in (.42, .3, .18):
                d.ellipse([X + s * (.5 - k), Y + s * (.5 - k), X + s * (.5 + k), Y + s * (.5 + k)], outline=c, width=int(1.6 * S))
        elif kind == 4:  # material
            d.ellipse([X + s * .1, Y + s * .1, X + s * .9, Y + s * .9], outline=c, width=int(2 * S))
            d.pieslice([X + s * .1, Y + s * .1, X + s * .9, Y + s * .9], 90, 270, fill=c)
        elif kind == 5:  # border
            for i in range(8):
                t0, t1 = i / 8, i / 8 + .07
                d.line([X + s * (.1 + .8 * t0), Y + s * .1, X + s * (.1 + .8 * t1), Y + s * .1], fill=c, width=int(2 * S))
                d.line([X + s * (.1 + .8 * t0), Y + s * .9, X + s * (.1 + .8 * t1), Y + s * .9], fill=c, width=int(2 * S))
                d.line([X + s * .1, Y + s * (.1 + .8 * t0), X + s * .1, Y + s * (.1 + .8 * t1)], fill=c, width=int(2 * S))
                d.line([X + s * .9, Y + s * (.1 + .8 * t0), X + s * .9, Y + s * (.1 + .8 * t1)], fill=c, width=int(2 * S))
        else:            # photo
            d.rounded_rectangle([X + s * .05, Y + s * .15, X + s * .95, Y + s * .85], radius=s * .1, outline=c, width=int(2 * S))
            d.polygon([(X + s * .15, Y + s * .78), (X + s * .42, Y + s * .45), (X + s * .62, Y + s * .7), (X + s * .72, Y + s * .58), (X + s * .88, Y + s * .78)], fill=c)
    page.shape(fn)

def home(dark):
    page = Page(dark)
    m, top = top_bar(page, '设置')
    width = W
    inner = min(max(100, width - 2 * m['edge']), 620)
    side = (width - inner) * .5
    y = top
    # header
    hh = 86
    page.glass((side, y, inner, hh))
    def avatar(d, x=side + 14, yy=y + (hh - 58) / 2):
        d.ellipse([x * S, yy * S, (x + 58) * S, (yy + 58) * S], fill=(84, 168, 220, 255))
        d.ellipse([(x + 21) * S, (yy + 14) * S, (x + 37) * S, (yy + 44) * S], fill=(255, 255, 255, 235))
    page.shape(avatar)
    ui_switch(page, side + inner - 16 - 51, y + (hh - 31) / 2)
    tx = side + 14 + 58 + 14
    page.write(tx, y + hh / 2 - 25 + 13, '微信 Liquid Glass', 20, 'Medium', anchor='lm')
    page.write(tx, y + hh / 2 + 3 + 9, '0.4.58 · TEST4 FIX58', 13, color=page.secondary, anchor='lm')
    y += hh + 24
    gap = 12
    column = (inner - gap) * .5
    height = max(98, round(column / 1.618))
    kind = 0
    for title, cards in CARDS:
        page.write(side + 6, y + 9, title, 13, 'Medium', color=page.secondary, anchor='lm')
        y += 18 + 8
        for i, (t, sub) in enumerate(cards):
            cx, cy = side + (i % 2) * (column + gap), y + (i // 2) * (height + gap)
            page.glass((cx, cy, column, height))
            pad = 15
            icon_placeholder(page, cx + pad, cy + pad - 1, kind, page.label); kind += 1
            page.write(cx + pad, cy + height - pad - 16 - 24 + 11, t, 17, 'Medium', anchor='lm', width=column - 2 * pad)
            page.write(cx + pad, cy + height - pad - 8, sub, 12.5, color=page.secondary, anchor='lm', width=column - 2 * pad)
        rows = (len(cards) + 1) // 2
        y += rows * height + (rows - 1) * gap + 26
    return page.image(), {'contentTop': top, 'column': column, 'cardHeight': height, 'contentEnd': y}

# ---------------------------------------------------------------- module (refraction / border)
def module(dark, title, scope, groups):
    page = Page(dark)
    m, top = top_bar(page, title)
    inner = min(max(100, W - 2 * m['edge']), 620)
    side = (W - inner) * .5
    y = top
    # range card
    page.write(side + 6, y + 9, '作用范围', 13, 'Medium', color=page.secondary, anchor='lm'); y += 26
    h = 46
    page.glass((side, y, inner, h))
    half = inner / 2
    sel = 0 if scope == 'dock' else 1
    def pill(d, yy=y):
        x0 = side + sel * half + 5
        d.rounded_rectangle([x0 * S, (yy + 5) * S, (x0 + half - 10) * S, (yy + h - 5) * S], radius=min(RADIUS - 5, (h - 10) / 2) * S,
                            fill=(255, 255, 255, 40) if dark else (0, 0, 0, 30))
    page.shape(pill)
    for i, t in enumerate(['底栏', '其余玻璃']):
        page.write(side + i * half + half / 2, y + h / 2, t, 15, 'Medium', color=page.label if i == sel else page.secondary, anchor='mm')
    y += h
    footer = '底栏：悬浮标签栏和按压时的透镜。其余玻璃：导航按钮、标题胶囊、输入栏、菜单等，以及这几页的卡片，调节时可直接看到。'
    lines = wrap(footer, 12.5, inner - 12)
    for k, line in enumerate(lines):
        page.write(side + 6, y + 7 + k * 15 + 7.5, line, 12.5, color=page.secondary, anchor='lm')
    y += 7 + 15 * len(lines) + 24
    for gtitle, rows, gfooter in groups:
        if y > H:
            break
        page.write(side + 6, y + 9, gtitle, 13, 'Medium', color=page.secondary, anchor='lm'); y += 26
        heights = [70 if r[0] == 'slider' else 52 for r in rows]
        page.glass((side, y, inner, sum(heights)))
        ry = y
        for k, (kind, label, value, t) in enumerate(rows):
            if k:
                page.shape(lambda d, yy=ry: d.line([(side + 16) * S, yy * S, (side + inner) * S, yy * S], fill=(255, 255, 255, 30) if dark else (0, 0, 0, 30), width=1))
            if kind == 'slider':
                page.write(side + 16, ry + 21, label, 15.5, 'Medium', anchor='lm', width=inner - 32 - 86)
                page.write(side + inner - 16, ry + 21, value, 13.5, color=page.secondary, anchor='rm')
                ui_slider(page, side + 16, ry + 36, inner - 32, t)
            else:
                page.write(side + 16, ry + 26, label, 15.5, 'Medium', anchor='lm')
                ui_switch(page, side + inner - 16 - 51, ry + (52 - 31) / 2, on=t > 0)
            ry += 70 if kind == 'slider' else 52
        y = ry
        if gfooter:
            lines = wrap(gfooter, 12.5, inner - 12)
            for k, line in enumerate(lines):
                page.write(side + 6, y + 7 + k * 15 + 7.5, line, 12.5, color=page.secondary, anchor='lm')
            y += 7 + 15 * len(lines)
        y += 24
    return page.image()

REFRACTION_DOCK = [
    ('底栏本体', [('slider', '折射强度', '1.15', 1.15 / 20), ('slider', 'RGB 色散', '0.95', .95 / 8), ('slider', '折射宽度', '10.0 pt', 9 / 59)],
     '底栏静止时的玻璃。按下时透镜从这里平滑过渡到下面的透镜参数。'),
    ('透镜（按压时）', [('slider', '透镜折射强度', '1.15', 1.15 / 20), ('slider', '透镜 RGB 色散', '0.95', .95 / 8),
                  ('slider', '透镜折射宽度（两端）', '10.0 pt', 9 / 59), ('slider', '上下折射宽度比例', '1.00', 1.0),
                  ('slider', '上下收窄曲线', '3.00', .4)], None)]
BORDER_OTHER = [
    ('浅色模式', [('slider', '不透明度', '0.65', .65), ('slider', '宽度', '0.65 pt', .325), ('slider', '亮度', '1.00', .5),
              ('slider', '左下 / 右上渐隐', '1.00', 1.0)], '亮度 1 为原色，低于 1 变暗，高于 1 向白色混合。渐隐只在左下和右上两条对角（iOS 26 的描边）。'),
    ('深色模式', [('slider', '不透明度', '0.14', .143), ('slider', '宽度', '0.65 pt', .325)], None)]

def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / 'ReferenceAnalysis/FIX58_settings_preview.png'
    shots = []
    light, info = home(False)
    shots.append(('首页 · 浅色', light))
    dark, _ = home(True)
    shots.append(('首页 · 深色', dark))
    shots.append(('折射强度和色散 · 底栏', module(False, '折射强度和色散', 'dock', REFRACTION_DOCK)))
    shots.append(('边框与渐隐 · 其余玻璃（深色）', module(True, '边框与渐隐', 'other', BORDER_OTHER)))
    gap, top = 40, 140
    sheet = Image.new('RGB', (len(shots) * W * S + (len(shots) + 1) * gap, H * S + top + gap), (246, 246, 248))
    d = ImageDraw.Draw(sheet)
    d.text((gap, 24), 'FIX58 设置页布局示意（与代码同一套尺寸；玻璃为示意画法，未画折射；图标为占位，真机用 SF Symbols）',
           font=ImageFont.truetype(FONTS + 'NotoSansCJK-Medium.ttc', 30, index=2), fill=(40, 40, 46))
    for i, (caption, img) in enumerate(shots):
        x = gap + i * (W * S + gap)
        mask = Image.new('L', img.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=48 * S, fill=255)
        sheet.paste(img.convert('RGB'), (x, top), mask)
        d.text((x + W * S / 2, top - 30), caption, font=ImageFont.truetype(FONTS + 'NotoSansCJK-Regular.ttc', 26, index=2),
               fill=(80, 80, 88), anchor='mm')
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, optimize=True)
    print(out, info)

if __name__ == '__main__':
    main()
