"""CPU model of the WeChatLiquidGlass dock (render-server mode): the scene, FIX54 and FIX56
(FIX47 / FIX57 lenses are in sim57.py).

Everything is in points; images are rendered at 3 px/pt like the device.
The lens overlay functions mirror WXGGlass.metal (sync path) line by line.
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import map_coordinates

SC = 3.0
FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'

# ----------------------------------------------------------------- helpers
def clamp(x, a, b):
    return np.minimum(b, np.maximum(a, x))

def sstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)

def capsule_field(x, y, w, h):
    """WXGCapsuleOpticalField (x, y relative to the centre)."""
    r = max(.5, min(w, h) * .5)
    qx = np.abs(x) - (w * .5 - r)
    qy = np.abs(y) - (h * .5 - r)
    ox = np.maximum(0, qx); oy = np.maximum(0, qy)
    length = np.sqrt(ox * ox + oy * oy)
    d = length + np.minimum(np.maximum(qx, qy), 0) - r
    nx = np.where(x < 0, -ox, ox) / np.maximum(length, 1e-4)
    ny = np.where(y < 0, -oy, oy) / np.maximum(length, 1e-4)
    return d, nx, ny

def shape(px, py, rect):
    x, y, w, h = rect
    return capsule_field(px - (x + w * .5), py - (y + h * .5), w, h)

def wxg_edge(d, width):
    return 1 - sstep(0, 1, np.maximum(-d, 0) / np.maximum(width, 1e-6))

def optical_offset(d, width, strength):
    width = np.maximum(width, 1e-6)
    t = clamp(-d / np.maximum(width, 1.0), 0, 1)
    edge = 1 - t * t * (3 - 2 * t)
    s = min(max(strength, 0.0), 20.0)
    amp = min(.32 * s, .40) + .32 * max(0.0, s - 2)
    return width * amp * edge * edge

def lens_edge_width(nx, ny, side, top_ratio, sharp):
    r = min(max(top_ratio, .05), 1.0)
    if r >= 1:
        return np.full_like(nx, side)
    l = np.sqrt(nx * nx + ny * ny)
    h = np.where(l > 1e-4, np.abs(nx) / np.maximum(l, 1e-9), 1.0)
    return side * (r + (1 - r) * h ** min(max(sharp, .5), 8))

def material_opacity(alpha, clear, edge, fade):
    op = min(max(alpha * (1.22 - .22 * min(max(clear, 0), 1)), 0), 1)
    return op * (1 - .82 * edge * edge * min(max(fade, 0), 1))

def rim_strength(nx, ny, fade, tl=0.0, br=0.0):
    t = clamp((np.abs(nx + ny) * .70710678 - .05) / .60, 0, 1)
    hl = t * t * (3 - 2 * t)
    side = 1 - .985 * min(max(fade, 0), 1)
    diag = 1 - np.where(nx + ny < 0, tl, br)
    return side + (diag - side) * hl

def over(dst_rgb, src_rgb, src_a):
    """src (straight colour, alpha) over dst (opaque)."""
    a = src_a[..., None]
    return dst_rgb * (1 - a) + src_rgb * a

def sample(img, x_pt, y_pt, origin, ppt):
    """Bilinear sample of an RGBA float image placed at `origin` (pt) with `ppt` px/pt."""
    cx = (x_pt - origin[0]) * ppt - .5
    cy = (y_pt - origin[1]) * ppt - .5
    out = np.stack([map_coordinates(img[..., c], [cy, cx], order=1, mode='nearest') for c in range(img.shape[2])], -1)
    return out

# ----------------------------------------------------------------- scene
class Params:
    def __init__(self, **kw):
        # geometry measured from the user's FIX54 screenshots (iPhone XS Max, 3x)
        self.bar_x0, self.bar_x1 = 18.0, 395.83          # drawn (pressed) bar
        self.bar_cy, self.bar_h = 843.58, 67.17
        self.bar_scale = 1.05                             # barGrowth at press 1
        self.lens_w, self.lens_h = 110.0, 79.83
        self.inset_pinch = .131                           # bodyPinch
        self.lens_refraction = 0.0                        # screenshots show no rim bending
        self.lens_edge = 20.26                            # FIX49 notes: user's value
        self.top_ratio = .305
        self.sharp = 3.0
        self.lens_zoom = 1.2
        self.lens_disp = 0.0
        self.border = .65                                 # bar / lens rim width (pt)
        self.rim_rgb = np.array([255., 255., 255.]); self.rim_a = .143; self.rim_fade = 1.0
        self.lens_rim_a = .143
        self.page = np.array([17., 17., 17.])
        self.tint = np.array([41., 41., 43.]); self.tint_a = .58; self.clear = 1.0; self.edge_fade = 0.0
        self.pattern = False
        self.view = (190.0, 796.0, 414.0, 892.0)          # rendered region (pt)
        for k, v in kw.items():
            setattr(self, k, v)

    @property
    def bar_w(self): return self.bar_x1 - self.bar_x0
    @property
    def bar_cx(self): return (self.bar_x0 + self.bar_x1) * .5
    def ubar(self):
        """u.bar: the unscaled material rect."""
        w, h = self.bar_w / self.bar_scale, self.bar_h / self.bar_scale
        return (self.bar_cx - w * .5, self.bar_cy - h * .5, w, h)
    def lens_rect(self, cx):
        return (cx - self.lens_w * .5, self.bar_cy - self.lens_h * .5, self.lens_w, self.lens_h)
    def inset(self):
        return self.bar_h * .5 * min(max(self.inset_pinch, 0), .3)
    def tab_centers(self):
        x, y, w, h = self.ubar(); gap = 6.0; slot = (w - 2 * gap) / 4
        return [x + gap + slot * (i + .5) for i in range(4)]

def make_icon_atlas(P, selected):
    """Atlas in unscaled bar space (u.bar coordinates), 6 px/pt, RGBA premultiplied-free."""
    ppt = 6
    x0, y0, x1, y1 = P.view[0] - 60, P.view[1] - 20, P.view[2] + 60, P.view[3] + 20
    W, H = int((x1 - x0) * ppt), int((y1 - y0) * ppt)
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(10.5 * ppt))
    ux, uy, uw, uh = P.ubar(); mid = uy + uh * .5
    names = ['微信', '通讯录', '发现', '我']
    for i, cx in enumerate(P.tab_centers()):
        col = (87, 190, 106, 255) if (selected and i == 3) or (selected and i != 3) else (170, 170, 170, 255)
        if not selected and i == 3:
            col = (170, 170, 170, 255)
        cy = mid - 8
        def X(v): return (v - x0) * ppt
        def Y(v): return (v - y0) * ppt
        if i == 3:   # person glyph
            d.ellipse([X(cx - 5.2), Y(cy - 11), X(cx + 5.2), Y(cy + 1)], fill=col)
            d.rounded_rectangle([X(cx - 11.5), Y(cy + 2.5), X(cx + 11.5), Y(cy + 11)], radius=int(4 * ppt), fill=col)
        elif i == 2:  # compass ring
            d.ellipse([X(cx - 11), Y(cy - 11), X(cx + 11), Y(cy + 11)], outline=col, width=int(1.6 * ppt))
            d.polygon([(X(cx + 5), Y(cy - 5)), (X(cx - 2), Y(cy - 1)), (X(cx + 1), Y(cy + 2))], fill=col)
        elif i == 1:
            d.ellipse([X(cx - 6), Y(cy - 10), X(cx + 4), Y(cy)], outline=col, width=int(1.6 * ppt))
            d.arc([X(cx - 12), Y(cy + 1), X(cx + 10), Y(cy + 20)], 180, 360, fill=col, width=int(1.6 * ppt))
            for k in range(3):
                d.line([X(cx + 6), Y(cy + 2 + 3 * k), X(cx + 13), Y(cy + 2 + 3 * k)], fill=col, width=int(1.4 * ppt))
        else:
            d.ellipse([X(cx - 12), Y(cy - 9), X(cx + 8), Y(cy + 8)], outline=col, width=int(1.6 * ppt))
        tw = d.textlength(names[i], font=font)
        d.text((X(cx) - tw / 2, Y(mid + 10) - 0.18 * 10.5 * ppt), names[i], font=font, fill=col)
    a = np.asarray(img).astype(float)
    rgb = a[..., :3]; al = a[..., 3:] / 255.
    return np.concatenate([rgb * al, al * 255.], -1), (x0, y0), ppt   # premultiplied (0..255)

def page_image(P, X, Y):
    if not P.pattern:
        return np.broadcast_to(P.page, X.shape + (3,)).copy()
    # thin diagonal stripes + a few horizontal lines, to make refraction visible
    v = ((X + Y) % 9.0 < .9).astype(float) * 30 + ((Y % 14.0) < .7).astype(float) * 25
    return P.page + v[..., None]

def grid(P):
    x0, y0, x1, y1 = P.view
    W, H = int(round((x1 - x0) * SC)), int(round((y1 - y0) * SC))
    xs = x0 + (np.arange(W) + .5) / SC
    ys = y0 + (np.arange(H) + .5) / SC
    return np.meshgrid(xs, ys)

def clip_cov(px, py, rect, aa=.5 / SC):
    d, _, _ = shape(px, py, rect)
    return 1 - sstep(-aa, aa, d), d

def rim_layer(px, py, rect, width, fade):
    """WXGRimView: a border of `width` inside the rounded rect, faded by direction."""
    d, nx, ny = shape(px, py, rect)
    aa = .5 / SC
    inside = 1 - sstep(-aa, aa, d)
    inner = 1 - sstep(-aa, aa, d + width)
    band = np.maximum(0, inside - inner)
    return band * rim_strength(nx, ny, fade)

# ----------------------------------------------------------------- lens overlay
def anchor_x(P, lens, wrap=4.0):
    """u.motion.w: the finger anchor in unscaled material coordinates (layout t from the lens x)."""
    t = (lens[0] - P.bar_x0 + wrap) / max(1.0, P.bar_w + 2 * wrap - lens[2])
    t = min(max(t, 0.0), 1.0)
    c = P.tab_centers()
    return c[0] + (c[3] - c[0]) * t

def lens_overlay(P, X, Y, lens, icons_sel, conv=(0.0, 0.0)):
    """WXGGlass.metal sync-mode lens path. conv (0, 0) is FIX54 (FIX46) exactly;
    FIX56: the bar seen through the lens uses the band converged by `conv`
    (left, right); icons keep FIX21's band. Returns premultiplied rgb, alpha."""
    ubar = P.ubar(); press = 1.0; ms = P.bar_scale
    bcx, bcy = ubar[0] + ubar[2] * .5, ubar[1] + ubar[3] * .5
    ld, lnx, lny = shape(X, Y, lens)
    zoom = 1 + press * (P.lens_zoom - 1)
    lw = lens_edge_width(lnx, lny, P.lens_edge, P.top_ratio, P.sharp)          # icons: FIX21 band
    edge = wxg_edge(ld, lw)
    off = optical_offset(ld, lw, P.lens_refraction) * press
    rx, ry = X - lnx * off, Y - lny * off
    chx, chy = lnx * (P.lens_disp * edge * 1.55 * press), lny * (P.lens_disp * edge * 1.55 * press)
    icx = anchor_x(P, lens)
    icy = bcy
    ix = icx + ((bcx + (rx - bcx) / ms) - icx) / zoom
    iy = icy + ((bcy + (ry - bcy) / ms) - icy) / zoom
    t = clamp(-ld / 1.25, 0, 1); inset = P.inset() * press * t * t * (3 - 2 * t)   # FIX44 contact band
    wb = lens_width_ends(lnx, lny, P.lens_edge, P.top_ratio, P.sharp, conv[0], conv[1])   # bar: FIX56 band
    ob = optical_offset(ld, wb, P.lens_refraction) * press
    bx, by = bcx + (X - lnx * ob - bcx) / ms, bcy + (Y - lny * ob - bcy) / ms
    sd, snx, sny = shape(bx, by, ubar)
    dd = sd * ms + inset
    return compose_inner(P, X, Y, dd, sd + inset / ms, snx, sny, ix, iy, chx, chy, icons_sel, zoom)

def compose_inner(P, X, Y, dd, sd_for_veil, snx, sny, ix, iy, chx, chy, icons_sel, zoom):
    aa = .8 / SC
    gy, gx = np.gradient(dd)
    fw = (np.abs(gx) + np.abs(gy))
    soft = np.maximum(aa, fw * .75)
    cv = 1 - sstep(-soft, soft, dd)
    em = wxg_edge(sd_for_veil, 10.0)                     # veil fade range (off unless edge_fade)
    veil = material_opacity(P.tint_a, P.clear, em, P.edge_fade) * cv
    acc_rgb = P.tint[None, None, :] * veil[..., None]
    acc_a = veil.copy()
    stroke = np.maximum(0, cv - (1 - sstep(-soft, soft, dd + P.border)))
    rs = rim_strength(snx, sny, P.rim_fade)
    sa = stroke * P.rim_a * rs
    acc_rgb = P.rim_rgb[None, None, :] * sa[..., None] + acc_rgb * (1 - sa[..., None])
    acc_a = sa + acc_a * (1 - sa)
    # icons (premultiplied), per-channel offsets
    img, origin, ppt = icons_sel
    ms = P.bar_scale
    cx_, cy_ = chx / (ms * zoom), chy / (ms * zoom)
    r = sample(img, ix + cx_, iy + cy_, origin, ppt)
    g = sample(img, ix, iy, origin, ppt)
    b = sample(img, ix - cx_, iy - cy_, origin, ppt)
    out_rgb = np.stack([r[..., 0] + acc_rgb[..., 0] * (1 - r[..., 3] / 255.),
                        g[..., 1] + acc_rgb[..., 1] * (1 - g[..., 3] / 255.),
                        b[..., 2] + acc_rgb[..., 2] * (1 - b[..., 3] / 255.)], -1)
    out_a = g[..., 3] / 255. + acc_a * (1 - g[..., 3] / 255.)
    return out_rgb, out_a

# ----------------------------------------------------------------- FIX56 model
def lens_width_ends(nx, ny, side, top_ratio, sharp, conv_l, conv_r):
    """WXGLensEdgeWidthEnds: FIX21's band, each side converged toward the top width."""
    r = min(max(top_ratio, .05), 1.0)
    if r >= 1:
        return np.full_like(nx, side)
    top = side * r
    l = np.sqrt(nx * nx + ny * ny)
    h = np.where(l > 1e-4, np.abs(nx) / np.maximum(l, 1e-9), 1.0)
    k = h ** min(max(sharp, .5), 8)
    c = np.where(nx < 0, conv_l, conv_r)
    return top + (side - top) * k * (1 - c)

def rounded_half_reach(w, h, radius, dy):
    """WXGRoundedHalfReach."""
    r = min(max(radius, .5), min(w, h) * .5) if radius > 0 else max(.5, min(w, h) * .5)
    ey = max(0.0, abs(dy) - (h * .5 - r))
    if ey > r:
        return -1.0
    return (w * .5 - r) + np.sqrt(max(0.0, r * r - ey * ey))

def end_convergence(P, lens, side):
    """WXGLensEndConvergence for the drawn bar (capsule) and the lens rect."""
    bx0, bx1, bh = P.bar_x0, P.bar_x1, P.bar_h
    lx0, lx1, lh = lens[0], lens[0] + lens[2], lens[3]
    reach = rounded_half_reach(lx1 - lx0, lh, 0.0, bh * .5)
    if not (lh > bh) or reach < 0:
        return 0.0
    rb = max(.5, min(bx1 - bx0, bh) * .5)
    c = (lx0 + lx1) * .5
    over = (bx0 + rb) - (c - reach) if side < 0 else (c + reach) - (bx1 - rb)
    t = min(max(over / 3.0, 0.0), 1.0); p = min(max((lh - bh) * .25, 0.0), 1.0)
    return t * t * (3 - 2 * t) * p * p * (3 - 2 * p)

def convergence(P, lens):
    return (end_convergence(P, lens, -1), end_convergence(P, lens, 1))

def mesh_convergence(conv):
    """WXGGlassView: the page mesh uses 1/8 steps."""
    return tuple(round(c * 8) / 8 for c in conv)

# ----------------------------------------------------------------- full frame
def render(P, lens_cx, version='fix54'):
    """One frame. version 'fix54' or 'fix56' (same scene, only the lens band at the ends differs)."""
    X, Y = grid(P)
    lens = P.lens_rect(lens_cx)
    conv = convergence(P, lens) if version == 'fix56' else (0.0, 0.0)
    icons_sel = make_icon_atlas(P, True) if not hasattr(P, '_sel') else P._sel
    icons_norm = make_icon_atlas(P, False) if not hasattr(P, '_norm') else P._norm
    P._sel, P._norm = icons_sel, icons_norm
    ms = P.bar_scale
    ubar = P.ubar(); bcx, bcy = ubar[0] + ubar[2] * .5, ubar[1] + ubar[3] * .5
    # 1. page
    out = page_image(P, X, Y)
    # 2. body
    body = (P.bar_x0, P.bar_cy - P.bar_h * .5, P.bar_w, P.bar_h)
    cov, bd = clip_cov(X, Y, body)
    full_d, fnx, fny = shape(X, Y, body)
    veil_k = material_opacity(P.tint_a, P.clear, wxg_edge(full_d, 10.0), P.edge_fade)
    body_rgb = over(page_image(P, X, Y), np.broadcast_to(P.tint, out.shape), veil_k)
    # body icons (normal), hidden inside the lens
    img, origin, ppt = icons_norm
    bx, by = bcx + (X - bcx) / ms, bcy + (Y - bcy) / ms
    ic = sample(img, bx, by, origin, ppt)
    ld, _, _ = shape(X, Y, lens)
    hide = 1 - sstep(-.5, .5, ld)
    a = ic[..., 3] / 255. * (1 - hide)
    body_rgb = body_rgb * (1 - a[..., None]) + ic[..., :3] * (1 - hide)[..., None]
    out = out * (1 - cov[..., None]) + body_rgb * cov[..., None]
    # 3. body rim
    rim = rim_layer(X, Y, body, P.border, P.rim_fade) * P.rim_a
    out = over(out, P.rim_rgb, rim)
    # 4. lens clip: page through the lens mesh + overlay
    lcov, _ = clip_cov(X, Y, lens)
    lens_bg = lens_backdrop(P, X, Y, lens, mesh_convergence(conv))
    o_rgb, o_a = lens_overlay(P, X, Y, lens, icons_sel, conv)
    lens_rgb = o_rgb + lens_bg * (1 - o_a[..., None])
    out = out * (1 - lcov[..., None]) + lens_rgb * lcov[..., None]
    # 5. lens rim
    lrim = rim_layer(X, Y, lens, P.border, P.rim_fade) * P.lens_rim_a
    out = over(out, P.rim_rgb, lrim)
    return np.clip(out, 0, 255).astype(np.uint8)

def lens_backdrop(P, X, Y, lens, conv=(0.0, 0.0)):
    """Page seen through the lens: WXGMeshSource lens mapping (per pixel, green channel)."""
    if not P.pattern:
        return page_image(P, X, Y)
    lcx, lcy = lens[0] + lens[2] * .5, lens[1] + lens[3] * .5
    d, nx, ny = shape(X, Y, lens)
    w = lens_width_ends(nx, ny, P.lens_edge, P.top_ratio, P.sharp, conv[0], conv[1])
    off = optical_offset(d, w, P.lens_refraction)
    za = P.lens_zoom
    rx, ry = X - nx * off, Y - ny * off
    sx, sy = lcx + (rx - lcx) / za, lcy + (ry - lcy) / za
    return page_image(P, sx, sy)

def band_width(P, lens, X, Y, conv=(0.0, 0.0)):
    """Refraction band width of the lens at each pixel (for the band figure)."""
    d, nx, ny = shape(X, Y, lens)
    return d, lens_width_ends(nx, ny, P.lens_edge, P.top_ratio, P.sharp, conv[0], conv[1])

def save(img, path, scale=1):
    im = Image.fromarray(img)
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im.save(path)
