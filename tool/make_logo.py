"""Reproducible logo pipeline (round 5, US-27).

Input : the untouched artwork (1024x1024 rounded square on off-white padding).
Output: assets/branding/*, iOS AppIcon set, Android adaptive + legacy icons, web favicon/PWA icons.
Usage : python tool/make_logo.py [path/to/source.png]     (needs Pillow)
The source is never modified; a byte copy is kept as assets/branding/logo_source.png.
"""
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\Asus\Downloads\klap_duay_kan_mhai_app_logo.png"
BR = os.path.join(ROOT, "assets", "branding")
os.makedirs(BR, exist_ok=True)
if os.path.abspath(SRC) != os.path.abspath(os.path.join(BR, "logo_source.png")):
    shutil.copyfile(SRC, os.path.join(BR, "logo_source.png"))
im = Image.open(os.path.join(BR, "logo_source.png")).convert("RGB")
W, H = im.size
px = im.load()


def colored(x, y):
    r, g, b = px[x, y]
    return (max(r, g, b) - min(r, g, b)) > 35 and min(r, g, b) < 215


def col_has(x):
    return sum(colored(x, y) for y in range(0, H, 4)) > 40


def row_has(y):
    return sum(colored(x, y) for x in range(0, W, 4)) > 40


# 1. bounding box of the artwork
x0 = next(x for x in range(W) if col_has(x))
x1 = next(x for x in range(W - 1, -1, -1) if col_has(x))
y0 = next(y for y in range(H) if row_has(y))
y1 = next(y for y in range(H - 1, -1, -1) if row_has(y))
print("artwork bbox", (x0, y0, x1, y1), "size", x1 - x0 + 1, y1 - y0 + 1)

# 2. largest centred square inside the bbox whose whole border ring is artwork colour
#    (inside the rounded corners: no off-white pixel left)
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
side_max = min(x1 - x0, y1 - y0) + 1


def ring_ok(l, t, s):
    pts = []
    for i in range(0, s, 2):
        for k in (0, 1, s - 1, s - 2):
            pts += [(l + i, t + k), (l + k, t + i)]
    return all(colored(min(W - 1, x), min(H - 1, y)) for x, y in pts)


side = side_max
while side > 400:
    l = int(round(cx - side / 2))
    t = int(round(cy - side / 2))
    if ring_ok(l, t, side):
        break
    side -= 2
side -= 8  # safety margin against anti-aliased edge pixels
l = int(round(cx - side / 2))
t = int(round(cy - side / 2))
print("crop square", (l, t, side))
master = im.crop((l, t, l + side, t + side)).resize((1024, 1024), Image.LANCZOS)
master.save(os.path.join(BR, "logo_master.png"), optimize=True)  # full-bleed, opaque, square


def gradient(size, scale=0.74):
    """Opaque background for adaptive/maskable art: a vertical gradient that continues the artwork outwards.
    Each row is a 55/45 blend of (a) the mean colour of the artwork's left/right edge columns (keeps the tone of
    the skyline band so there is no visible box) and (b) a plain top-to-bottom blue->green ramp (stops the
    skyline silhouettes from turning into a dark horizon band)."""
    L = int(round(1024 / scale))
    m = (L - 1024) // 2
    rows = []
    for y in range(1024):
        acc = [0, 0, 0]
        n = 0
        for x in list(range(0, 24, 3)) + list(range(1000, 1024, 3)):
            p = master.getpixel((x, y))
            for k in range(3):
                acc[k] += p[k]
            n += 1
        rows.append(tuple(a / n for a in acc))
    sm = []
    for y in range(1024):
        lo, hi = max(0, y - 60), min(1024, y + 61)
        sm.append(tuple(sum(r[k] for r in rows[lo:hi]) / (hi - lo) for k in range(3)))
    top, bot = sm[0], sm[-1]
    col = Image.new("RGB", (1, L))
    for y in range(L):
        yy = min(1023, max(0, y - m))
        t = yy / 1023
        ramp = tuple(top[k] + (bot[k] - top[k]) * t for k in range(3))
        col.putpixel((0, y), tuple(round(0.55 * sm[yy][k] + 0.45 * ramp[k]) for k in range(3)))
    return col.resize((L, L), Image.NEAREST).resize((size, size), Image.LANCZOS)


def rounded(img, radius_frac):
    s = img.size[0]
    m = Image.new("L", (s * 4, s * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=int(s * 4 * radius_frac), fill=255)
    out = img.convert("RGBA")
    out.putalpha(m.resize((s, s), Image.LANCZOS))
    return out


def circle(img):
    s = img.size[0]
    m = Image.new("L", (s * 4, s * 4), 0)
    ImageDraw.Draw(m).ellipse((0, 0, s * 4 - 1, s * 4 - 1), fill=255)
    out = img.convert("RGBA")
    out.putalpha(m.resize((s, s), Image.LANCZOS))
    return out


def feathered_art(size, scale, feather=0.03):
    s = int(size * scale)
    art = master.resize((s, s), Image.LANCZOS).convert("RGBA")
    f = max(2, int(s * feather))
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).rectangle((f, f, s - f, s - f), fill=255)
    art.putalpha(m.filter(ImageFilter.GaussianBlur(f / 2)))
    return art


def on_gradient(size, scale):
    bg = gradient(size, scale).convert("RGBA")
    art = feathered_art(size, scale)
    bg.alpha_composite(art, ((size - art.size[0]) // 2, (size - art.size[1]) // 2))
    return bg


def save(img, *parts, rgb=False):
    p = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    (img.convert("RGB") if rgb else img).save(p, optimize=True)


# 3. in-app mark: transparent rounded square (splash / onboarding / sign-in)
rounded(master.resize((512, 512), Image.LANCZOS), 0.22).save(os.path.join(BR, "logo_mark.png"), optimize=True)

# 4. iOS: full-bleed, no alpha, every size listed in Contents.json
ios_dir = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
cj = json.load(open(os.path.join(ios_dir, "Contents.json")))
for e in cj["images"]:
    n = float(e["size"].split("x")[0])
    sc = int(e["scale"][0])
    p = round(n * sc)
    master.resize((p, p), Image.LANCZOS).convert("RGB").save(os.path.join(ios_dir, e["filename"]), optimize=True)

# 5. Android: adaptive (108dp layers at xxxhdpi = 432 px) + legacy mipmaps
res = ("android", "app", "src", "main", "res")
save(gradient(432), *res, "drawable-nodpi", "ic_launcher_background.png", rgb=True)
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
art = feathered_art(432, 0.74)
fg.alpha_composite(art, ((432 - art.size[0]) // 2, (432 - art.size[1]) // 2))
save(fg, *res, "drawable-nodpi", "ic_launcher_foreground.png")
any_dir = os.path.join(ROOT, *res, "mipmap-anydpi-v26")
os.makedirs(any_dir, exist_ok=True)
xml = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
    "</adaptive-icon>\n"
)
for n in ("ic_launcher.xml", "ic_launcher_round.xml"):
    with open(os.path.join(any_dir, n), "w", newline="\n") as fh:
        fh.write(xml)
for d, s in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    sq = master.resize((s, s), Image.LANCZOS)
    save(rounded(sq, 0.18), *res, f"mipmap-{d}", "ic_launcher.png")
    save(circle(sq), *res, f"mipmap-{d}", "ic_launcher_round.png")

# 6. web: favicon, apple-touch, PWA any + maskable (safe zone: artwork at 72 %)
save(master.resize((32, 32), Image.LANCZOS), "web", "favicon.png")
master.resize((48, 48), Image.LANCZOS).save(os.path.join(ROOT, "web", "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)])
for s in (192, 512):
    save(master.resize((s, s), Image.LANCZOS), "web", "icons", f"Icon-{s}.png", rgb=True)
    save(on_gradient(s, 0.72), "web", "icons", f"Icon-maskable-{s}.png", rgb=True)
save(master.resize((180, 180), Image.LANCZOS), "web", "icons", "apple-touch-icon.png", rgb=True)

# 7. review sheet (not shipped): adaptive icon under three masks + small sizes
sheet = Image.new("RGB", (1000, 230), (236, 236, 236))
adaptive = on_gradient(432, 0.74)
x = 10
for shape in ("circle", "squircle", "rounded"):
    if shape == "circle":
        tile = circle(adaptive.convert("RGB"))
    else:
        tile = rounded(adaptive.convert("RGB"), 0.3 if shape == "squircle" else 0.18)
    tile = tile.resize((200, 200), Image.LANCZOS)
    sheet.paste(tile, (x, 10), tile)
    x += 210
for s in (96, 48, 32, 16):
    sheet.paste(master.resize((s, s), Image.LANCZOS), (x, 10))
    x += s + 10
sheet.save(os.path.join(os.environ.get("TEMP", "."), "logo_review.png"))
print("done; master crop side", side)
