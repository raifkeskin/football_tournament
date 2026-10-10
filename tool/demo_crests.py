"""Demo takımları için tek şablonlu yuvarlak arma üretici.
Kullanım: python3 tool/demo_crests.py assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf <çıktı klasörü>
(Pillow gerekir.) Çıktılar storage media/teams/demo/ altına yüklenir.

Şablon: dış halka (ikincil renk) + ince beyaz halka + takım renginde
degrade zemin, çapraz şeritler, üstte lige özel simge, ortada baş harfler.
"""
import math, os, sys, json
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

FONT = sys.argv[1]
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)
S = 1024  # çizim boyutu; 512'ye küçültülür

# (lig, ad, dosya, baş harf, ana renk, ikincil renk)
TEAMS = [
    # Demo Masterlar Ligi — simge: üç yıldız
    ('m', 'Kuzey Yıldızları', 'kuzey-yildizlari', 'KY', '#B91C1C', '#F5C542'),
    ('m', 'Galata Veteranlar', 'galata-veteranlar', 'GV', '#1D4ED8', '#F5C542'),
    ('m', 'Bakırköy Dostluk', 'bakirkoy-dostluk', 'BD', '#047857', '#F8FAFC'),
    ('m', 'Florya Kartalları', 'florya-kartallari', 'FK', '#111827', '#E5E7EB'),
    ('m', 'Şişli Efsaneler', 'sisli-efsaneler', 'ŞE', '#EA580C', '#1F2937'),
    ('m', 'Eyüp Sultanlar', 'eyup-sultanlar', 'ES', '#6D28D9', '#F5C542'),
    ('m', 'Beylikdüzü Masterlar', 'beylikduzu-masterlar', 'BM', '#BE185D', '#F8FAFC'),
    ('m', 'Haliç Spor', 'halic-spor', 'HS', '#1E3A8A', '#38BDF8'),
    ('m', 'Moda Masterlar', 'moda-masterlar', 'MM', '#CA8A04', '#1E293B'),
    ('m', 'Üsküdar Dostlar', 'uskudar-dostlar', 'ÜD', '#334155', '#F59E0B'),
    ('m', 'Ataşehir Yıldızları', 'atasehir-yildizlari', 'AY', '#15803D', '#FACC15'),
    ('m', 'Maltepe Sahil', 'maltepe-sahil', 'MS', '#0369A1', '#F8FAFC'),
    ('m', 'Kartal Veteranlar', 'kartal-veteranlar', 'KV', '#9F1239', '#F5C542'),
    ('m', 'Pendik Denizciler', 'pendik-denizciler', 'PD', '#0F766E', '#F8FAFC'),
    ('m', 'Çekmeköy Kurtları', 'cekmekoy-kurtlari', 'ÇK', '#C2410C', '#111827'),
    ('m', 'Beykoz Efsaneleri', 'beykoz-efsaneleri', 'BE', '#4D7C0F', '#F5C542'),
    # Demo Okul Kupası — simge: tek büyük yıldız
    ('o', 'Yıldız Koleji', 'yildiz-koleji', 'YK', '#B91C1C', '#F8FAFC'),
    ('o', 'Bilim Ortaokulu', 'bilim-ortaokulu', 'BO', '#1D4ED8', '#FACC15'),
    ('o', 'Deniz Anadolu Lisesi', 'deniz-anadolu-lisesi', 'DAL', '#0E7490', '#F8FAFC'),
    ('o', 'Çınar Koleji', 'cinar-koleji', 'ÇK', '#166534', '#FACC15'),
    ('o', 'Ufuk Ortaokulu', 'ufuk-ortaokulu', 'UO', '#EA580C', '#F8FAFC'),
    ('o', 'Gökkuşağı Koleji', 'gokkusagi-koleji', 'GK', '#7C3AED', '#FDE047'),
    # Demo Şirketler Halısaha Ligi — simge: top
    ('s', 'Kuzey Lojistik', 'kuzey-lojistik', 'KL', '#1E40AF', '#F97316'),
    ('s', 'Mavi Yazılım', 'mavi-yazilim', 'MY', '#0284C7', '#F8FAFC'),
    ('s', 'Atlas İnşaat', 'atlas-insaat', 'Aİ', '#B45309', '#111827'),
    ('s', 'Pusula Sigorta', 'pusula-sigorta', 'PS', '#0F766E', '#FACC15'),
    ('s', 'Zirve Enerji', 'zirve-enerji', 'ZE', '#DC2626', '#F8FAFC'),
    ('s', 'Defne Gıda', 'defne-gida', 'DG', '#15803D', '#F8FAFC'),
    ('s', 'Orion Bilişim', 'orion-bilisim', 'OB', '#4C1D95', '#22D3EE'),
    ('s', 'Ekin Tekstil', 'ekin-tekstil', 'ET', '#BE123C', '#F5C542'),
]


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def star(cx, cy, r, rot=-90):
    pts = []
    for k in range(10):
        rr = r if k % 2 == 0 else r * 0.42
        a = math.radians(rot + k * 36)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def ball(d, cx, cy, r, fg, bg):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fg)
    # orta beşgen + kenarlara uzanan çizgiler
    pent = [(cx + r * 0.42 * math.cos(math.radians(-90 + k * 72)),
             cy + r * 0.42 * math.sin(math.radians(-90 + k * 72))) for k in range(5)]
    d.polygon(pent, fill=bg)
    for k in range(5):
        a = math.radians(-90 + k * 72)
        p = pent[k]
        q = (cx + r * 0.95 * math.cos(a), cy + r * 0.95 * math.sin(a))
        d.line([p, q], fill=bg, width=max(2, int(r * 0.12)))


def crest(league, initials, c1h, c2h):
    c1, c2 = rgb(c1h), rgb(c2h)
    white = (248, 250, 252)
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cx = cy = S / 2
    R = S / 2 - 6

    # Dış halka: ikincil renk, üstten alta hafif degrade
    ring = Image.new('RGBA', (S, S))
    rd = ImageDraw.Draw(ring)
    for y in range(S):
        rd.line([(0, y), (S, y)], fill=mix(mix(c2, white, 0.25), mix(c2, (0, 0, 0), 0.18), y / S) + (255,))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
    img.paste(ring, (0, 0), mask)

    # İnce ayırıcı halka (zemin rengine karşıt)
    d = ImageDraw.Draw(img)
    r2 = R * 0.86
    sep = white if lum(c2) < 170 else mix(c1, (0, 0, 0), 0.35)
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=sep)

    # Zemin: takım rengi, sol üstten sağ alta degrade + çapraz şeritler
    r3 = R * 0.80
    field = Image.new('RGBA', (S, S))
    fd = ImageDraw.Draw(field)
    light, dark = mix(c1, white, 0.22), mix(c1, (0, 0, 0), 0.30)
    for y in range(S):
        fd.line([(0, y), (S, y)], fill=mix(light, dark, y / S) + (255,))
    stripes = Image.new('L', (S, S), 0)
    sd = ImageDraw.Draw(stripes)
    w = S * 0.09
    for k in range(-12, 12):
        x0 = k * w * 2
        sd.polygon([(x0, 0), (x0 + w, 0), (x0 + w + S, S), (x0 + S, S)], fill=34)
    field = Image.composite(Image.new('RGBA', (S, S), (0, 0, 0, 255)), field, stripes)
    fmask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(fmask).ellipse([cx - r3, cy - r3, cx + r3, cy + r3], fill=255)
    img.paste(field, (0, 0), fmask)

    # Parlaklık: üst yarıda yumuşak beyaz yay
    gloss = Image.new('L', (S, S), 0)
    ImageDraw.Draw(gloss).ellipse([cx - r3 * 1.5, cy - r3 * 2.25, cx + r3 * 1.5, cy - r3 * 0.05], fill=30)
    gloss = ImageChops.multiply(gloss, fmask).filter(ImageFilter.GaussianBlur(8))
    img = Image.composite(Image.new('RGBA', (S, S), white + (255,)), img, gloss)
    d = ImageDraw.Draw(img)

    # Baş harfler (gölgeli)
    n = len(initials)
    size = int(S * (0.40 if n <= 2 else 0.31))
    font = ImageFont.truetype(FONT, size)
    tx, ty = cx, cy + S * 0.035
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((tx + 8, ty + 10), initials, font=font, anchor='mm', fill=(0, 0, 0, 120))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)))
    d = ImageDraw.Draw(img)
    d.text((tx, ty), initials, font=font, anchor='mm', fill=white,
           stroke_width=6, stroke_fill=mix(c1, (0, 0, 0), 0.45))

    # Lig simgesi (ikincil renkte; açık ikincilde bile zeminde okunur)
    acc = c2 if lum(c2) > 90 else white
    top = cy - r3 * 0.66
    if league == 'm':
        for dx, rr in ((-0.17, 0.065), (0, 0.085), (0.17, 0.065)):
            d.polygon(star(cx + S * dx, top + (0 if dx == 0 else S * 0.02), S * rr), fill=acc)
    elif league == 'o':
        d.polygon(star(cx, top, S * 0.09), fill=acc)
    else:
        ball(d, cx, top + S * 0.01, S * 0.088, acc, mix(c1, (0, 0, 0), 0.2))
    # Alt: kısa çizgi + iki nokta (kulüp arması hissi)
    by = cy + r3 * 0.70
    d.rounded_rectangle([cx - S * 0.12, by - S * 0.012, cx + S * 0.12, by + S * 0.012], radius=S * 0.012, fill=acc)

    return img.resize((256, 256), Image.LANCZOS)


tiles = []
for lg, name, slug, ini, a, b in TEAMS:
    im = crest(lg, ini, a, b)
    im.save(os.path.join(OUT, slug + '.webp'), quality=88, method=6)
    tiles.append(im)

# Kontrol sayfası: büyük + uygulamadaki küçük boyutlar (koyu/açık zemin)
cols, cell = 8, 150
rows = math.ceil(len(tiles) / cols)
sheet = Image.new('RGB', (cols * cell, rows * cell + 120), (245, 245, 245))
for i, im in enumerate(tiles):
    sheet.paste(im.resize((130, 130), Image.LANCZOS), ((i % cols) * cell + 10, (i // cols) * cell + 10), im.resize((130, 130), Image.LANCZOS))
y0 = rows * cell
ImageDraw.Draw(sheet).rectangle([0, y0 + 60, cols * cell, y0 + 120], fill=(15, 23, 42))
for i, im in enumerate(tiles):
    t = im.resize((28, 28), Image.LANCZOS)
    sheet.paste(t, (10 + i * 38, y0 + 16), t)
    sheet.paste(t, (10 + i * 38, y0 + 76), t)
sheet.save(os.path.join(OUT, '_sheet.png'))
print(len(tiles), 'arma')
