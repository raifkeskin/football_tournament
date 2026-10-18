"""Demo turnuvaları için kalkan biçimli lig logosu üretici.
Kullanım: python3 tool/demo_league_logos.py assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf <çıktı klasörü>
(Pillow gerekir.) Çıktılar storage media/leagues/demo/ altına yüklenir.

Şablon: ikincil renkte kalın kenarlı kalkan, tema renginde degrade zemin,
üstte kupa, ortada iki satır lig adı, altta yıldızlar.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = sys.argv[1]
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)
S = 1024

# (dosya, üst satır, alt satır, ana renk, kenar rengi, vurgu rengi)
LEAGUES = [
    ('masterlar-ligi', 'MASTERLAR', 'LİGİ', '#C8102E', '#F8FAFC', '#F5C542'),
    ('okul-kupasi', 'OKUL', 'KUPASI', '#1D4ED8', '#F59E0B', '#F59E0B'),
    ('sirketler-ligi', 'ŞİRKETLER', 'LİGİ', '#0B3B5C', '#F97316', '#F97316'),
]


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def shield(inset):
    """Kalkan çokgeni: düz üst, dik yanlar, alt yarıda uca inen eğriler."""
    l, r, t, b = S * 0.13 + inset, S * 0.87 - inset, S * 0.05 + inset, S * 0.96 - inset
    cx, side = S / 2, t + (b - t) * 0.58
    pts = [(l, t), (r, t), (r, side)]

    def bez(p0, p1, p2):
        return [((1 - u) ** 2 * p0[0] + 2 * (1 - u) * u * p1[0] + u * u * p2[0],
                 (1 - u) ** 2 * p0[1] + 2 * (1 - u) * u * p1[1] + u * u * p2[1])
                for u in (k / 24 for k in range(1, 25))]

    pts += bez((r, side), (r, b - (b - t) * 0.12), (cx, b))
    pts += bez((cx, b), (l, b - (b - t) * 0.12), (l, side))
    return pts


def trophy(d, cx, top, w, col):
    h = w * 0.95
    # kase
    d.pieslice([cx - w / 2, top - h * 0.45, cx + w / 2, top + h * 0.55], 0, 180, fill=col)
    d.rectangle([cx - w / 2, top - h * 0.02, cx + w / 2, top + h * 0.06], fill=col)
    # kulplar
    hw = w * 0.07
    for sgn in (-1, 1):
        x0 = cx + sgn * w / 2
        box = [min(x0, x0 + sgn * w * 0.24), top + h * 0.02, max(x0, x0 + sgn * w * 0.24), top + h * 0.34]
        d.arc(box, 270 if sgn > 0 else 90, 90 if sgn > 0 else 270, fill=col, width=int(hw))
    # gövde + taban
    d.rectangle([cx - w * 0.07, top + h * 0.50, cx + w * 0.07, top + h * 0.72], fill=col)
    d.rounded_rectangle([cx - w * 0.30, top + h * 0.70, cx + w * 0.30, top + h * 0.84], radius=w * 0.04, fill=col)


def star(cx, cy, r):
    import math
    pts = []
    for k in range(10):
        rr = r if k % 2 == 0 else r * 0.42
        a = math.radians(-90 + k * 36)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def logo(top_text, bottom_text, c1h, c2h, acch):
    c1, c2, acc = rgb(c1h), rgb(c2h), rgb(acch)
    white = (248, 250, 252)
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))

    # Gölge
    sh = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(x, y + 14) for x, y in shield(0)], fill=(0, 0, 0, 110))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))

    d = ImageDraw.Draw(img)
    d.polygon(shield(0), fill=c2)
    d.polygon(shield(S * 0.035), fill=mix(c1, (0, 0, 0), 0.45))

    # Zemin degradesi
    field = Image.new('RGBA', (S, S))
    fd = ImageDraw.Draw(field)
    light, dark = mix(c1, white, 0.18), mix(c1, (0, 0, 0), 0.35)
    for y in range(S):
        fd.line([(0, y), (S, y)], fill=mix(light, dark, y / S) + (255,))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).polygon(shield(S * 0.05), fill=255)
    img.paste(field, (0, 0), mask)
    # Üst yarıda parlaklık
    gloss = Image.new('L', (S, S), 0)
    ImageDraw.Draw(gloss).ellipse([-S * 0.2, -S * 0.75, S * 1.2, S * 0.42], fill=26)
    gloss = Image.composite(gloss, Image.new('L', (S, S), 0), mask).filter(ImageFilter.GaussianBlur(10))
    img = Image.composite(Image.new('RGBA', (S, S), white + (255,)), img, gloss)
    d = ImageDraw.Draw(img)

    trophy(d, S / 2, S * 0.16, S * 0.24, acc)

    def text(y, s, size):
        font = ImageFont.truetype(FONT, size)
        while d.textlength(s, font=font) > S * 0.60:
            size -= 4
            font = ImageFont.truetype(FONT, size)
        d.text((S / 2 + 6, y + 8), s, font=font, anchor='mm', fill=(0, 0, 0, 90))
        d.text((S / 2, y), s, font=font, anchor='mm', fill=white,
               stroke_width=5, stroke_fill=mix(c1, (0, 0, 0), 0.55))

    text(S * 0.47, top_text, int(S * 0.14))
    # ayırıcı çizgi
    d.rounded_rectangle([S * 0.32, S * 0.545, S * 0.68, S * 0.557], radius=S * 0.006, fill=acc)
    text(S * 0.615, bottom_text, int(S * 0.105))
    for dx in (-0.075, 0, 0.075):
        d.polygon(star(S / 2 + S * dx, S * 0.735 + (0 if dx == 0 else -S * 0.005), S * (0.032 if dx == 0 else 0.025)), fill=acc)
    return img.resize((512, 512), Image.LANCZOS)


sheet = Image.new('RGB', (3 * 300, 300 + 70), (245, 245, 245))
ImageDraw.Draw(sheet).rectangle([0, 300, 900, 370], fill=(15, 23, 42))
for i, (slug, a, b, c1, c2, acc) in enumerate(LEAGUES):
    im = logo(a, b, c1, c2, acc)
    im.save(os.path.join(OUT, slug + '.png'), optimize=True)
    t = im.resize((260, 260), Image.LANCZOS)
    sheet.paste(t, (i * 300 + 20, 20), t)
    s = im.resize((48, 48), Image.LANCZOS)
    sheet.paste(s, (i * 300 + 126, 311), s)
sheet.save(os.path.join(OUT, '_sheet.png'))
print(len(LEAGUES), 'logo')
