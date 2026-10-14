"""FIX47 / FIX57 lens models on top of wxgsim (same scene and geometry: the
user's FIX54 screenshots).

FIX47 (the base of FIX57): 45-degree inner inset (WXGInnerInset grows over as
many points as it is deep) and the per-pixel band WXGLensEdgeWidthAtBar
(narrows to the top width where the pixel lies outside the drawn bar, 4 pt
blend), used for icons, the inner bar and the page mesh alike.
FIX57: FIX47, plus the end term for the inner bar and the page only
(WXGLensEndReach / WXGLensEndRelax: `end_reach`, `converge`); the page mesh
uses it in 1/8 steps like WXGGlassView.m. `join` (shortening the 45-degree join
at a relaxed end) was tried and not used.
"""
import numpy as np
import wxgsim as W
from wxgsim import clamp, shape, optical_offset, wxg_edge, compose_inner, anchor_x

def sstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)

def inset47(P, ld, press=1.0, short=None):
    """FIX47 inset: grows over as many points as it is deep (45 degrees). `short`
    (array 0..1, optional): per pixel, how far that ramp is shortened to the
    FIX46 1.25 pt contact band."""
    full = P.inset() * press
    L = max(1.25, full)
    if short is not None:
        L = L + (1.25 - L) * short
    t = clamp(-ld / L, 0, 1)
    return full * t * t * (3 - 2 * t)

def width_at_bar(nx, ny, side, ratio, sharp, bar_dist):
    """WXGLensEdgeWidthAtBar (FIX47)."""
    r = min(max(ratio, .05), 1.0)
    if r >= 1:
        return np.full_like(nx, side)
    l = np.sqrt(nx * nx + ny * ny)
    h = np.where(l > 1e-4, np.abs(nx) / np.maximum(l, 1e-9), 1.0)
    t = sstep((bar_dist + 4.0) / 8.0)
    return side * (r + (1 - r) * h ** min(max(sharp, .5), 8) * (1 - t))

def converge(w, nx, top, conv):
    """End term: each side's band pulled toward the top width by conv (left, right)."""
    c = np.where(nx < 0, conv[0], conv[1])
    return top + (w - top) * (1 - c)

def drawn_bar_distance(P, X, Y):
    ubar = P.ubar(); ms = P.bar_scale
    bcx, bcy = ubar[0] + ubar[2] * .5, ubar[1] + ubar[3] * .5
    d, _, _ = shape(bcx + (X - bcx) / ms, bcy + (Y - bcy) / ms, ubar)
    return d * ms

def overlay47(P, X, Y, lens, icons_sel, conv=(0.0, 0.0), join=(0.0, 0.0)):
    ubar = P.ubar(); press = 1.0; ms = P.bar_scale
    bcx, bcy = ubar[0] + ubar[2] * .5, ubar[1] + ubar[3] * .5
    ld, lnx, lny = shape(X, Y, lens)
    zoom = 1 + press * (P.lens_zoom - 1)
    w47 = width_at_bar(lnx, lny, P.lens_edge, P.top_ratio, P.sharp, drawn_bar_distance(P, X, Y))
    edge = wxg_edge(ld, w47)
    off = optical_offset(ld, w47, P.lens_refraction) * press
    rx, ry = X - lnx * off, Y - lny * off
    chx, chy = lnx * (P.lens_disp * edge * 1.55 * press), lny * (P.lens_disp * edge * 1.55 * press)
    icx, icy = anchor_x(P, lens), bcy
    ix = icx + ((bcx + (rx - bcx) / ms) - icx) / zoom
    iy = icy + ((bcy + (ry - bcy) / ms) - icy) / zoom
    top = P.lens_edge * min(max(P.top_ratio, .05), 1.0)
    wb = converge(w47, lnx, top, conv)
    ob = optical_offset(ld, wb, P.lens_refraction) * press
    bx, by = bcx + (X - lnx * ob - bcx) / ms, bcy + (Y - lny * ob - bcy) / ms
    sd, snx, sny = shape(bx, by, ubar)
    ins = inset47(P, ld, press, short=np.where(lnx < 0, join[0], join[1]))
    dd = sd * ms + ins
    return compose_inner(P, X, Y, dd, sd + ins / ms, snx, sny, ix, iy, chx, chy, icons_sel, zoom)

def backdrop47(P, X, Y, lens, conv=(0.0, 0.0)):
    if not P.pattern and P.page_fn is None:
        return W.page_image(P, X, Y)
    lcx, lcy = lens[0] + lens[2] * .5, lens[1] + lens[3] * .5
    d, nx, ny = shape(X, Y, lens)
    bar = (P.bar_x0, P.bar_cy - P.bar_h * .5, P.bar_w, P.bar_h)
    bd, _, _ = shape(X, Y, bar)
    w = width_at_bar(nx, ny, P.lens_edge, P.top_ratio, P.sharp, bd)
    top = P.lens_edge * min(max(P.top_ratio, .05), 1.0)
    w = converge(w, nx, top, tuple(round(c * 8) / 8 for c in conv))   # WXGGlassView.m: 1/8 steps
    off = optical_offset(d, w, P.lens_refraction)
    sx, sy = lcx + (X - nx * off - lcx) / P.lens_zoom, lcy + (Y - ny * off - lcy) / P.lens_zoom
    return page(P, sx, sy)

def page(P, X, Y):
    if P.page_fn is not None:
        return P.page_fn(X, Y)
    return W.page_image(P, X, Y)

def render(P, lens_cx, conv=(0.0, 0.0), join=(0.0, 0.0)):
    """FIX47 frame with an optional end term (conv per side, inner bar + page only)."""
    X, Y = W.grid(P)
    lens = P.lens_rect(lens_cx)
    if not hasattr(P, '_sel'):
        P._sel, P._norm = W.make_icon_atlas(P, True), W.make_icon_atlas(P, False)
    ms = P.bar_scale
    ubar = P.ubar(); bcx, bcy = ubar[0] + ubar[2] * .5, ubar[1] + ubar[3] * .5
    out = page(P, X, Y).astype(float)
    body = (P.bar_x0, P.bar_cy - P.bar_h * .5, P.bar_w, P.bar_h)
    cov, _ = W.clip_cov(X, Y, body)
    full_d, _, _ = shape(X, Y, body)
    k = W.material_opacity(P.tint_a, P.clear, wxg_edge(full_d, 10.0), P.edge_fade)
    body_rgb = W.over(out, np.broadcast_to(P.tint, out.shape), k)
    img, origin, ppt = P._norm
    ic = W.sample(img, bcx + (X - bcx) / ms, bcy + (Y - bcy) / ms, origin, ppt)
    ld, _, _ = shape(X, Y, lens)
    hide = 1 - W.sstep(-.5, .5, ld)
    a = ic[..., 3] / 255. * (1 - hide)
    body_rgb = body_rgb * (1 - a[..., None]) + ic[..., :3] * (1 - hide)[..., None]
    out = out * (1 - cov[..., None]) + body_rgb * cov[..., None]
    out = W.over(out, P.rim_rgb, W.rim_layer(X, Y, body, P.border, P.rim_fade) * P.rim_a)
    lcov, _ = W.clip_cov(X, Y, lens)
    bg = backdrop47(P, X, Y, lens, conv)
    o_rgb, o_a = overlay47(P, X, Y, lens, P._sel, conv, join)
    out = out * (1 - lcov[..., None]) + (o_rgb + bg * (1 - o_a[..., None])) * lcov[..., None]
    out = W.over(out, P.rim_rgb, W.rim_layer(X, Y, lens, P.lens_border, P.rim_fade) * P.lens_rim_a)
    return np.clip(out, 0, 255).astype(np.uint8)

def light_params(**kw):
    """Light appearance close to the user's FIX47 screenshot (page 236, bar 245)."""
    P = W.Params(lens_refraction=4.21, **kw)
    P.page = np.array([232., 232., 232.]); P.tint = np.array([255., 255., 255.]); P.tint_a = .55
    P.rim_rgb = np.array([255., 255., 255.]); P.rim_a = .9; P.lens_rim_a = .95; P.border = 1.0; P.lens_border = 1.6
    P.page_fn = None
    return P

def end_reach(P, lens, side, start=10.0, done=2.0):
    """FIX57 end term: 0 until the lens's outer edge is `start` pt short of the
    bar's end, smoothstep to 1 once it is `done` pt past it."""
    lx0, lx1 = lens[0], lens[0] + lens[2]
    over = (P.bar_x0 - lx0) if side < 0 else (lx1 - P.bar_x1)
    return float(sstep((over + start) / (start + done)))

def reach_pair(P, lens, start=10.0, done=2.0):
    return (end_reach(P, lens, -1, start, done), end_reach(P, lens, 1, start, done))
