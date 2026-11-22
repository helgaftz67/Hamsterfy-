import sys
from PIL import Image, ImageDraw, ImageFilter

SS = 4            # supersampling
N = 1024 * SS     # working canvas


def gradient(size, top, bottom):
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        c = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = c
    return img


def ell(d, cx, cy, rx, ry, fill):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)


def note(d, x, y, k, color):
    """A small eighth note; k is its height."""
    ell(d, x, y, k * 0.26, k * 0.20, color)
    w = max(2, int(k * 0.11))
    d.line([x + k * 0.20, y, x + k * 0.20, y - k * 0.80], fill=color, width=w)
    d.polygon([(x + k * 0.20, y - k * 0.80), (x + k * 0.62, y - k * 0.56), (x + k * 0.62, y - k * 0.34),
               (x + k * 0.20, y - k * 0.56)], fill=color)


def hamster(layer, cx, cy, s, fur, muzzle, ear_in, eye, shine, blush, nose, band, cup, cup_in, ring=None):
    """One original hamster face wearing headphones. s is the head half-width."""
    d = ImageDraw.Draw(layer)
    # round head with full cheeks
    ell(d, cx, cy, s * 0.98, s * 0.88, fur)
    for sx in (-1, 1):
        ell(d, cx + sx * s * 0.60, cy + s * 0.34, s * 0.50, s * 0.42, fur)
    ell(d, cx, cy + s * 0.40, s * 0.40, s * 0.28, muzzle)
    # headphones: band over the head, cups on the sides
    r = s * 1.04
    d.arc([cx - r, cy - s * 0.97, cx + r, cy + s * 0.97], start=192, end=348, fill=band, width=int(s * 0.14))
    for sx in (-1, 1):
        d.rounded_rectangle([cx + sx * s * 1.02 - s * 0.19, cy - s * 0.30, cx + sx * s * 1.02 + s * 0.19, cy + s * 0.34],
                            radius=s * 0.17, fill=cup)
        d.rounded_rectangle([cx + sx * s * 1.02 - s * 0.08, cy - s * 0.16, cx + sx * s * 1.02 + s * 0.08, cy + s * 0.20],
                            radius=s * 0.07, fill=cup_in)
    # small round ears
    for sx in (-1, 1):
        ell(d, cx + sx * s * 0.60, cy - s * 0.72, s * 0.23, s * 0.23, fur)
        ell(d, cx + sx * s * 0.60, cy - s * 0.70, s * 0.125, s * 0.125, ear_in)
    # big low-set eyes with two highlights
    for sx in (-1, 1):
        ex, ey = cx + sx * s * 0.40, cy + s * 0.08
        if ring:
            ell(d, ex, ey, s * 0.17, s * 0.195, ring)
        ell(d, ex, ey, s * 0.135, s * 0.16, eye)
        ell(d, ex + s * 0.045, ey - s * 0.06, s * 0.05, s * 0.05, shine)
        ell(d, ex - s * 0.045, ey + s * 0.06, s * 0.025, s * 0.025, shine)
    # blush under the eyes
    for sx in (-1, 1):
        ell(d, cx + sx * s * 0.64, cy + s * 0.36, s * 0.15, s * 0.09, blush)
    # tiny nose and smile
    ell(d, cx, cy + s * 0.27, s * 0.06, s * 0.045, nose)
    w = max(2, int(s * 0.032))
    for sx in (-1, 1):
        d.arc([cx + (sx - 1) * s * 0.075, cy + s * 0.26, cx + (sx + 1) * s * 0.075, cy + s * 0.42],
              start=0, end=180, fill=nose, width=w)


def mascots(scale=1.0):
    """Transparent layer with the white and the black hamster, centred."""
    layer = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    c = N / 2
    s = N * 0.172 * scale
    off = s * 1.22
    cy = c + s * 0.22
    sh = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sh)
    for sx in (-1, 1):
        ell(ds, c + sx * off, cy + s * 0.34, s * 1.2, s * 0.95, (40, 20, 24, 110))
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(N * 0.014)))
    amber = (255, 231, 163, 255)  # cream, as in the app
    black = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    hamster(black, c + off, cy, s, (34, 29, 50, 255), (62, 55, 86, 255), (154, 120, 150, 255),
            (20, 16, 32, 255), (255, 255, 255, 255), (199, 122, 156, 255), (255, 176, 196, 255),
            (252, 250, 255, 255), (252, 250, 255, 255), amber, ring=(250, 248, 255, 255))
    layer.alpha_composite(black.rotate(8, resample=Image.BICUBIC, center=(c + off, cy)))
    white = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    hamster(white, c - off, cy, s, (253, 251, 255, 255), (255, 255, 255, 255), (255, 198, 212, 255),
            (34, 29, 50, 255), (255, 255, 255, 255), (255, 160, 184, 255), (240, 120, 150, 255),
            (34, 29, 50, 255), (34, 29, 50, 255), amber)
    layer.alpha_composite(white.rotate(-8, resample=Image.BICUBIC, center=(c - off, cy)))
    # notes floating between and above them
    d = ImageDraw.Draw(layer)
    note(d, c - s * 0.22, cy - s * 1.20, s * 0.62, (255, 255, 255, 255))
    note(d, c + s * 0.42, cy - s * 1.62, s * 0.44, (255, 240, 186, 255))
    return layer


def background():
    """Dusk: slate blue through mauve to peach and orange, with the dark
    of the horizon sitting in the glow at the bottom."""
    stops = [(0.0, (74, 84, 121)), (0.34, (111, 102, 136)), (0.62, (185, 130, 133)),
             (0.84, (240, 150, 106)), (1.0, (242, 110, 46))]
    img = Image.new('RGB', (N, N))
    px = img.load()
    for y in range(N):
        t = y / (N - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t <= t1:
                k = (t - t0) / (t1 - t0)
                row = tuple(round(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
                break
        for x in range(N):
            px[x, y] = row
    img = img.convert('RGBA')
    horizon = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    ell(ImageDraw.Draw(horizon), N * 0.5, N * 0.97, N * 0.34, N * 0.085, (26, 15, 12, 205))
    img.alpha_composite(horizon.filter(ImageFilter.GaussianBlur(N * 0.03)))
    return img


out = sys.argv[1]
bg = background()
full = bg.copy()
full.alpha_composite(mascots(1.0))
full.resize((1024, 1024), Image.LANCZOS).save(f'{out}/icon_full.png')
# adaptive layers: content must fit the central 61% safe zone
fg = mascots(0.66)
fg.resize((432, 432), Image.LANCZOS).save(f'{out}/ic_launcher_foreground.png')
bg.resize((432, 432), Image.LANCZOS).convert('RGB').save(f'{out}/ic_launcher_background.png')
# legacy icons: rounded square
mask = Image.new('L', (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, N, N], radius=N * 0.22, fill=255)
legacy = Image.new('RGBA', (N, N), (0, 0, 0, 0))
legacy.paste(full, (0, 0), mask)
for name, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    legacy.resize((px, px), Image.LANCZOS).save(f'{out}/ic_launcher_{name}.png')
