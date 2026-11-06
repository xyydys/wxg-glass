#!/usr/bin/env python3
"""FIX116 A/B: a picture of the home "+" menu's entrance and exit (WXGMenuCascade.h).

The numbers come from the very header the plugin is built with (dump.c, built
here with cc); the glass is only a stand-in (white, blurred background, thin rim),
so the rows' *motion* is what to judge, not the material.

usage: python3 tools/menu_cascade/preview.py <out dir> [--stagger 0.034] [--speed 1]
writes <out dir>/menu_entrance.gif and menu_entrance_strip.png, and (FIX116 B)
menu_cycle.gif (open, hold, close) and menu_exit_strip.png"""
import csv, io, math, os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
S = 3                       # pixels per point
W, H = 340, 440             # the picture, in points
PLUS = (292, 44)            # the "+" glass' centre
ICON = 44; CAP_H = 34; GAP = 9; PAD = 17; PITCH = 58; FIRST = 112
TITLES = ["发起群聊", "添加朋友", "扫一扫", "收付款", "一键已读", "清理会话"]

def font(size, weight="Bold"):
    for path in ("/usr/share/fonts/opentype/noto/NotoSansCJK-%s.ttc" % weight,
                 "/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc"):
        if os.path.exists(path):
            return ImageFont.truetype(path, int(size * S), index=2)   # index 2: SC
    return ImageFont.load_default()

def background():
    img = Image.new("RGB", (W * S, H * S), (244, 244, 246))
    d = ImageDraw.Draw(img)
    for i in range(H * S):                                  # a soft vertical wash
        v = int(246 - 14 * i / (H * S))
        d.line([(0, i), (W * S, i)], fill=(v, v, v + 1))
    leaf = Image.new("L", img.size, 0)
    ld = ImageDraw.Draw(leaf)
    import random
    random.seed(7)
    for _ in range(90):                                     # leaves behind the "+", like the video
        x = random.gauss(W * .86 * S, 46 * S); y = random.gauss(70 * S, 46 * S); r = random.uniform(4, 11) * S
        ld.ellipse([x - r, y - r * .6, x + r, y + r * .6], fill=random.randint(60, 150))
    leaf = leaf.filter(ImageFilter.GaussianBlur(1.4 * S))
    dark = Image.new("RGB", img.size, (92, 96, 94))
    img = Image.composite(dark, img, leaf)
    for k, y in enumerate((172, 292, 398)):                 # a few list rows far behind
        ImageDraw.Draw(img).rounded_rectangle([14 * S, y * S, 250 * S, (y + 62) * S], 24 * S, outline=(228, 228, 230), width=2 * S)
    return img

def glass(blur_bg, w, h, radius, alpha_boost=1.0):
    """A w x h pt glass sprite (RGBA, S px per pt), cut from the blurred background at its place."""
    pw, ph = int(w * S), int(h * S)
    sprite = Image.new("RGBA", (pw + 16 * S, ph + 16 * S), (0, 0, 0, 0))
    ox = oy = 8 * S
    shadow = Image.new("L", sprite.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle([ox, oy + 3 * S, ox + pw, oy + ph + 3 * S], radius * S, fill=60)
    shadow = shadow.filter(ImageFilter.GaussianBlur(6 * S))
    sprite.paste((60, 62, 66, 255), (0, 0), shadow)
    body = Image.new("RGBA", (pw, ph), (255, 255, 255, int(150 * alpha_boost)))
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1], radius * S, fill=255)
    sprite.paste(body, (ox, oy), mask)
    rim = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.rounded_rectangle([0, 0, pw - 1, ph - 1], radius * S, outline=(255, 255, 255, 235), width=int(1.4 * S))
    rd.rounded_rectangle([int(2 * S), int(2 * S), pw - 1 - int(2 * S), ph - 1 - int(2 * S)], max(1, radius - 2) * S, outline=(190, 192, 198, 70), width=int(1 * S))
    sprite.alpha_composite(rim, (ox, oy))
    return sprite, (ox, oy)

def icon_glyph(kind, size_px, color=(40, 42, 46, 255)):
    im = Image.new("RGBA", (size_px, size_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(im); u = size_px / 24.0
    if kind == 0:   # group chat
        d.rounded_rectangle([3 * u, 5 * u, 20 * u, 17 * u], 4 * u, fill=color); d.polygon([(8 * u, 17 * u), (8 * u, 22 * u), (13 * u, 17 * u)], fill=color)
    elif kind == 1: # person +
        d.ellipse([6 * u, 3 * u, 14 * u, 11 * u], fill=color); d.rounded_rectangle([3 * u, 13 * u, 17 * u, 22 * u], 5 * u, fill=color)
        d.ellipse([14 * u, 13 * u, 23 * u, 22 * u], fill=(150, 152, 158, 255)); d.rectangle([17.4 * u, 15 * u, 19.6 * u, 20 * u], fill=(255, 255, 255, 255)); d.rectangle([15.5 * u, 16.9 * u, 21.5 * u, 18.1 * u], fill=(255, 255, 255, 255))
    elif kind == 2: # scan
        for (x, y, dx, dy) in ((3, 3, 1, 1), (21, 3, -1, 1), (3, 21, 1, -1), (21, 21, -1, -1)):
            d.line([(x * u, y * u), ((x + 5 * dx) * u, y * u)], fill=color, width=int(2.4 * u)); d.line([(x * u, y * u), (x * u, (y + 5 * dy) * u)], fill=color, width=int(2.4 * u))
        d.rectangle([5 * u, 11 * u, 19 * u, 13 * u], fill=color)
    elif kind == 3: # card
        d.rounded_rectangle([3 * u, 6 * u, 21 * u, 19 * u], 3.5 * u, fill=color); d.rectangle([3 * u, 10 * u, 21 * u, 12.5 * u], fill=(255, 255, 255, 255))
    elif kind == 4: # read
        d.line([(3 * u, 13 * u), (8 * u, 18 * u), (16 * u, 7 * u)], fill=color, width=int(2.8 * u), joint="curve"); d.line([(12 * u, 17 * u), (14 * u, 19 * u), (21 * u, 8 * u)], fill=color, width=int(2.8 * u), joint="curve")
    else:           # clean
        d.polygon([(4 * u, 5 * u), (20 * u, 5 * u), (18 * u, 20 * u), (6 * u, 20 * u)], fill=color); d.rectangle([2 * u, 3 * u, 22 * u, 5 * u], fill=color)
    return im

def run_dump(stagger, speed, step, until, half, leaving=False):
    exe = os.path.join(tempfile.mkdtemp(), "dump")
    subprocess.check_call(["cc", "-std=c11", "-O2", "-Wall", "-Wextra", os.path.join(HERE, "dump.c"), "-lm", "-o", exe])
    out = subprocess.check_output([exe, str(len(TITLES)), str(PITCH), str(stagger), str(speed), str(step), str(until), str(half)] + (["exit"] if leaving else [])).decode()
    rows = {}
    for r in csv.DictReader(io.StringIO(out)):
        rows.setdefault(int(r["row"]), []).append({k: float(v) for k, v in r.items()})
    return rows

def paste_scaled(canvas, sprite, anchor_px, centre_px, sx, sy, dx_px, dy_px, alpha):
    """Paste `sprite` scaled by (sx, sy) about its own centre, then moved by (dx, dy), with opacity alpha."""
    if alpha <= 0.004 or sx <= 0.01 or sy <= 0.01:
        return
    w, h = sprite.size
    nw, nh = max(1, int(w * sx)), max(1, int(h * sy))
    sc = sprite.resize((nw, nh), Image.LANCZOS)
    if alpha < 1:
        a = sc.getchannel("A").point(lambda v: int(v * alpha)); sc.putalpha(a)
    canvas.alpha_composite(sc, (int(centre_px[0] + dx_px - nw / 2), int(centre_px[1] + dy_px - nh / 2)))

def main():
    out_dir = sys.argv[1]; os.makedirs(out_dir, exist_ok=True)
    stagger = float(sys.argv[sys.argv.index("--stagger") + 1]) if "--stagger" in sys.argv else 0.034
    speed = float(sys.argv[sys.argv.index("--speed") + 1]) if "--speed" in sys.argv else 1.0
    fps = 50; step = 1.0 / fps; until = 0.9
    bg = background(); blur = bg.filter(ImageFilter.GaussianBlur(5 * S)).convert("RGBA")
    f_title = font(CAP_H * .47); f_plus = None
    # static sprites per row
    sprites = []
    for i, title in enumerate(TITLES):
        mid = FIRST + i * PITCH
        tw = f_title.getlength(title) / S
        cw = max(CAP_H * 1.7, math.ceil(tw) + 2 * PAD)
        icon_box = (PLUS[0] - ICON / 2, mid - ICON / 2)
        cap_box = (icon_box[0] - GAP - cw, mid - CAP_H / 2)
        g_icon, off = glass(blur, ICON, ICON, ICON / 2)
        # content on the glass: the backdrop is cut from the blurred background at the row's slot
        crop = blur.crop((int((icon_box[0]) * S) - off[0], int((icon_box[1]) * S) - off[1], int((icon_box[0] + ICON) * S) + off[0], int((icon_box[1] + ICON) * S) + off[1]))
        base = crop.copy(); base.alpha_composite(g_icon)
        # keep only the shape (shadow + glass) of the sprite, over the blurred crop inside the glass
        mask = Image.new("L", g_icon.size, 0); ImageDraw.Draw(mask).rounded_rectangle([off[0], off[1], off[0] + ICON * S - 1, off[1] + ICON * S - 1], ICON / 2 * S, fill=255)
        ic = Image.new("RGBA", g_icon.size, (0, 0, 0, 0)); ic.paste(crop, (0, 0), mask); ic.alpha_composite(g_icon)
        glyph = icon_glyph(i, int(22 * S)); ic.alpha_composite(glyph, (int(g_icon.size[0] / 2 - glyph.size[0] / 2), int(g_icon.size[1] / 2 - glyph.size[1] / 2)))
        g_cap, offc = glass(blur, cw, CAP_H, CAP_H / 2)
        crop2 = blur.crop((int(cap_box[0] * S) - offc[0], int(cap_box[1] * S) - offc[1], int((cap_box[0] + cw) * S) + offc[0], int((cap_box[1] + CAP_H) * S) + offc[1]))
        mask2 = Image.new("L", g_cap.size, 0); ImageDraw.Draw(mask2).rounded_rectangle([offc[0], offc[1], offc[0] + cw * S - 1, offc[1] + CAP_H * S - 1], CAP_H / 2 * S, fill=255)
        cap = Image.new("RGBA", g_cap.size, (0, 0, 0, 0)); cap.paste(crop2, (0, 0), mask2); cap.alpha_composite(g_cap)
        text = Image.new("RGBA", g_cap.size, (0, 0, 0, 0))
        ImageDraw.Draw(text).text((g_cap.size[0] / 2, g_cap.size[1] / 2), title, font=f_title, fill=(24, 26, 30, 255), anchor="mm")
        sprites.append(dict(mid=mid, icon=ic, cap=cap, text=text, icon_c=(icon_box[0] + ICON / 2, mid), cap_c=(cap_box[0] + cw / 2, mid), cw=cw))
    half_by_row = [s["cw"] / 2 for s in sprites]
    # one dump per row's half width (the capsule's right edge depends on it)
    poses = [run_dump(stagger, speed, step, until, half_by_row[i])[i] for i in range(len(TITLES))]
    exits = [run_dump(stagger, speed, step, 0.6, half_by_row[i], True)[i] for i in range(len(TITLES))]

    def draw(table, k):
        canvas = bg.convert("RGBA")
        # the "+" itself, at rest
        pg, po = glass(blur, ICON, ICON, ICON / 2)
        pm = Image.new("L", pg.size, 0); ImageDraw.Draw(pm).rounded_rectangle([po[0], po[1], po[0] + ICON * S - 1, po[1] + ICON * S - 1], ICON / 2 * S, fill=255)
        pc = blur.crop((int((PLUS[0] - ICON / 2) * S) - po[0], int((PLUS[1] - ICON / 2) * S) - po[1], int((PLUS[0] + ICON / 2) * S) + po[0], int((PLUS[1] + ICON / 2) * S) + po[1]))
        plus = Image.new("RGBA", pg.size, (0, 0, 0, 0)); plus.paste(pc, (0, 0), pm); plus.alpha_composite(pg)
        d = ImageDraw.Draw(plus); cx, cy = pg.size[0] / 2, pg.size[1] / 2; u = 8 * S
        d.line([(cx - u, cy), (cx + u, cy)], fill=(30, 32, 36, 255), width=int(2.6 * S)); d.line([(cx, cy - u), (cx, cy + u)], fill=(30, 32, 36, 255), width=int(2.6 * S))
        canvas.alpha_composite(plus, (int(PLUS[0] * S - pg.size[0] / 2), int(PLUS[1] * S - pg.size[1] / 2)))
        for i, sp in enumerate(sprites):
            p = table[i][k]
            paste_scaled(canvas, sp["icon"], None, (sp["icon_c"][0] * S, sp["icon_c"][1] * S), p["iconScale"], p["iconScale"], 0, p["iconDy"] * S, p["iconAlpha"])
            cap = sp["cap"].copy()
            if p["textAlpha"] > 0.004:
                t = sp["text"].copy(); t.putalpha(t.getchannel("A").point(lambda v, a=p["textAlpha"]: int(v * a)))
                shifted = Image.new("RGBA", t.size, (0, 0, 0, 0)); shifted.paste(t, (int(-p["textDx"] * S), 0))   # slides out from the icon: starts to the right
                cap.alpha_composite(shifted)
            paste_scaled(canvas, cap, None, (sp["cap_c"][0] * S, sp["cap_c"][1] * S), p["capScaleX"], p["capScaleY"], p["capDx"] * S, p["capDy"] * S, p["capAlpha"])
        return canvas.convert("RGB")
    frames = [draw(poses, k) for k in range(len(poses[0]))]
    out_frames = [draw(exits, k) for k in range(len(exits[0]))]
    small = [f.resize((W * 2, H * 2), Image.LANCZOS) for f in frames]
    hold = [small[-1]] * 40
    small[0].save(os.path.join(out_dir, "menu_entrance.gif"), save_all=True, append_images=small[1:] + hold, duration=int(1000 / fps), loop=0, optimize=False)
    pick = [3, 6, 9, 12, 15, 18, 22, 28, 40]
    cell = 2
    strip = Image.new("RGB", (W * cell * len(pick) // 2, H * cell // 2 + 22), "white")
    dd = ImageDraw.Draw(strip)
    for n, k in enumerate(pick):
        k = min(k, len(frames) - 1)
        im = frames[k].resize((W * cell // 2, H * cell // 2), Image.LANCZOS)
        strip.paste(im, (n * W * cell // 2, 22)); dd.text((n * W * cell // 2 + 6, 4), "%d ms" % round(k * 1000 / fps), fill=(0, 0, 0))
    strip.save(os.path.join(out_dir, "menu_entrance_strip.png"))
    # FIX116 B: open, hold, close, empty
    cyc = [f.resize((W * 2, H * 2), Image.LANCZOS) for f in out_frames]
    cycle = small[:] + [small[-1]] * 36 + cyc + [cyc[-1]] * 30
    cycle[0].save(os.path.join(out_dir, "menu_cycle.gif"), save_all=True, append_images=cycle[1:], duration=int(1000 / fps), loop=0, optimize=False)
    pick = [0, 3, 6, 9, 12, 15, 18, 22, 28]
    strip = Image.new("RGB", (W * cell * len(pick) // 2, H * cell // 2 + 22), "white")
    dd = ImageDraw.Draw(strip)
    for n, k in enumerate(pick):
        k = min(k, len(out_frames) - 1)
        im = out_frames[k].resize((W * cell // 2, H * cell // 2), Image.LANCZOS)
        strip.paste(im, (n * W * cell // 2, 22)); dd.text((n * W * cell // 2 + 6, 4), "close %d ms" % round(k * 1000 / fps), fill=(0, 0, 0))
    strip.save(os.path.join(out_dir, "menu_exit_strip.png"))
    print("wrote", os.path.join(out_dir, "menu_entrance.gif"), "menu_entrance_strip.png, menu_cycle.gif, menu_exit_strip.png", len(frames), "+", len(out_frames), "frames")

main()
