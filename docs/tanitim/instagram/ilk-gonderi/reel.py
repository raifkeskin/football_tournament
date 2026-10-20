"""Lig Masası tanıtım Reels'i: 1080x1920, 30 fps kareler (Pillow) -> ffmpeg.

Kullanım: python reel.py <images_dir> <out_dir> [--stills]
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

IMG = sys.argv[1]
OUT = sys.argv[2]
STILLS = '--stills' in sys.argv
ROOT = '/Users/raifkeskin/football_tournament'
FONTS = ROOT + '/assets/fonts/'
CREST = ROOT + '/design/logo-lm/lm-arma-yuvarlak-1024.png'

W, H, FPS = 1080, 1920, 30
GOLD = (224, 165, 38)
WHITE = (255, 255, 255)
MUTED = (176, 190, 206)
GREEN = (16, 185, 129)


def font(name, size):
    return ImageFont.truetype(FONTS + name, size)


F_HEAD = font('BarlowCondensed-ExtraBoldItalic.ttf', 104)
F_HEAD_BIG = font('BarlowCondensed-ExtraBoldItalic.ttf', 150)
F_SUB = font('Barlow-SemiBold.ttf', 40)
F_TAG = font('Barlow-Bold.ttf', 30)
F_SMALL = font('Barlow-Medium.ttf', 34)


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def ease_in_out(t):
    t = max(0.0, min(1.0, t))
    return 3 * t * t - 2 * t * t * t


# ---------------------------------------------------------------- arka plan
def make_background(top=(11, 61, 36)):
    bg = Image.new('RGB', (W, H))
    mid, bot = (15, 23, 42), (8, 12, 24)
    px = bg.load()
    for y in range(H):
        t = y / H
        if t < 0.45:
            k = t / 0.45
            c = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.45) / 0.55
            c = tuple(int(mid[i] + (bot[i] - mid[i]) * k) for i in range(3))
        for x in range(W):
            px[x, y] = c
    # Silik saha çizgileri.
    lines = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lines)
    a = (255, 255, 255, 14)
    d.ellipse([W / 2 - 300, H / 2 - 300, W / 2 + 300, H / 2 + 300], outline=a, width=4)
    d.line([0, H / 2, W, H / 2], fill=a, width=4)
    d.rectangle([W / 2 - 330, H - 330, W / 2 + 330, H + 10], outline=a, width=4)
    bg = Image.alpha_composite(bg.convert('RGBA'), lines)
    # Üstte hafif altın parıltı.
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-200, -500, W + 200, 500], fill=(224, 165, 38, 30))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    return Image.alpha_composite(bg, glow)


BG = make_background()


# ---------------------------------------------------------------- telefon
SCREEN_W = 690
CROP = (0, 97, 945, 2010)  # durum çubuğu ve alttaki jest çubuğu kırpılır
RADIUS = 58
BEZEL = 16


def load_screen(n):
    return Image.open(os.path.join(IMG, f'{n}.jpg')).convert('RGB')


def rounded_mask(size, r):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], r, fill=255)
    return m


def phone(img, crop=CROP):
    """Ekran görüntüsünü çerçeveli, gölgeli telefon görseline çevirir."""
    img = img.crop(crop) if crop else img
    sh = round(img.height * SCREEN_W / img.width)
    img = img.resize((SCREEN_W, sh), Image.LANCZOS)
    pw, ph = SCREEN_W + 2 * BEZEL, sh + 2 * BEZEL
    pad = 70
    out = Image.new('RGBA', (pw + 2 * pad, ph + 2 * pad), (0, 0, 0, 0))
    # Gölge + yeşil hale.
    sh_layer = Image.new('RGBA', out.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh_layer).rounded_rectangle(
        [pad + 10, pad + 30, pad + pw - 10, pad + ph + 10], RADIUS + BEZEL, fill=(0, 0, 0, 170))
    sh_layer = sh_layer.filter(ImageFilter.GaussianBlur(36))
    out = Image.alpha_composite(out, sh_layer)
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([pad, pad, pad + pw, pad + ph], RADIUS + BEZEL, fill=(6, 9, 16, 255),
                        outline=(58, 72, 98, 255), width=3)
    out.paste(img, (pad + BEZEL, pad + BEZEL), rounded_mask(img.size, RADIUS))
    return out


# ---------------------------------------------------------------- ekran düzeltmeleri
def fix_home(img):
    """45: yöneticiye özel 'kart cezası onayı' satırı çıkarılır."""
    a, b = 886, 1058
    top = img.crop((0, 0, img.width, a))
    rest = img.crop((0, b, img.width, img.height))
    out = Image.new('RGB', img.size, (15, 23, 42))
    out.paste(top, (0, 0))
    out.paste(rest, (0, a))
    return out


def fix_stream(img):
    """33: başka maça ait YouTube kapağı yerine çizilmiş saha görseli."""
    x0, y0, x1, y1 = 32, 660, 913, 1157
    w, h = x1 - x0, y1 - y0
    f = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(f)
    stripes = 9
    for i in range(stripes):
        c = (34, 120, 58) if i % 2 == 0 else (30, 108, 52)
        d.rectangle([i * w / stripes, 0, (i + 1) * w / stripes, h], fill=c)
    line = (220, 240, 225)
    m = 26
    d.rectangle([m, m, w - m, h - m], outline=line, width=4)
    d.line([w / 2, m, w / 2, h - m], fill=line, width=4)
    d.ellipse([w / 2 - 80, h / 2 - 80, w / 2 + 80, h / 2 + 80], outline=line, width=4)
    d.rectangle([m, h / 2 - 120, m + 120, h / 2 + 120], outline=line, width=4)
    d.rectangle([w - m - 120, h / 2 - 120, w - m, h / 2 + 120], outline=line, width=4)
    # Oyuncular (iki takım rengi).
    import random
    rnd = random.Random(7)
    for k in range(10):
        for side, col in ((0, (250, 204, 21)), (1, (240, 253, 250))):
            px = rnd.uniform(0.12, 0.48) * w + side * 0.4 * w
            py = rnd.uniform(0.12, 0.88) * h
            d.ellipse([px - 11, py - 11, px + 11, py + 11], fill=col, outline=(15, 23, 42), width=3)
    f = f.filter(ImageFilter.GaussianBlur(1.2))
    # Hafif karartma + oynat düğmesi.
    shade = Image.new('RGBA', f.size, (0, 0, 0, 70))
    f = Image.alpha_composite(f.convert('RGBA'), shade)
    d = ImageDraw.Draw(f)
    cx, cy, r = w / 2, h / 2, 74
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 235))
    d.polygon([(cx - 22, cy - 34), (cx - 22, cy + 34), (cx + 36, cy)], fill=(15, 23, 42))
    # CANLI etiketi.
    d.rounded_rectangle([30, 30, 190, 84], 27, fill=(229, 56, 59))
    d.ellipse([48, 48, 66, 66], fill=WHITE)
    d.text((78, 36), 'CANLI', font=font('Barlow-Bold.ttf', 34), fill=WHITE)
    # İzlemek için dokun.
    d.polygon([(40, h - 62), (40, h - 36), (62, h - 49)], fill=WHITE)
    d.text((76, h - 70), 'İzlemek için dokun', font=font('Barlow-SemiBold.ttf', 32), fill=WHITE)
    mask = rounded_mask(f.size, 18)
    img = img.copy()
    img.paste(f.convert('RGB'), (x0, y0), mask)
    return img


# ---------------------------------------------------------------- metin
def text_center(d, y, s, f, fill, alpha=255):
    w = d.textlength(s, font=f)
    d.text(((W - w) / 2, y), s, font=f, fill=fill + (alpha,))


def headline(canvas, title, sub, t):
    """Başlık ve alt yazı: aşağıdan kayarak belirir."""
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k = ease_out(t / 0.45)
    dy = (1 - k) * 40
    a = int(255 * k)
    text_center(d, 150 + dy, title, F_HEAD, WHITE, a)
    if sub:
        k2 = ease_out((t - 0.12) / 0.45)
        text_center(d, 272 + (1 - k2) * 30, sub, F_SUB, MUTED, int(255 * k2))
    # Altın çizgi.
    lw = 120 * k
    d.rounded_rectangle([W / 2 - lw / 2, 128 + dy, W / 2 + lw / 2, 136 + dy], 4, fill=GOLD + (a,))
    return Image.alpha_composite(canvas, layer)


def place_phone(canvas, ph, t, dur, enter=True):
    k = ease_out(t / 0.55) if enter else 1.0
    zoom = 1.0 + 0.025 * (t / dur)
    pw, phh = round(ph.width * zoom), round(ph.height * zoom)
    img = ph.resize((pw, phh), Image.BICUBIC) if zoom != 1.0 else ph
    x = (W - pw) // 2
    y = round(350 + (1 - k) * 260)
    if k < 1:
        img = img.copy()
        alpha = img.getchannel('A').point(lambda v: int(v * k))
        img.putalpha(alpha)
    canvas.alpha_composite(img, (x, y))
    return canvas


# ---------------------------------------------------------------- sahneler
crest = Image.open(CREST).convert('RGBA')


def intro(t, dur):
    c = BG.copy()
    k = ease_out(t / 0.8)
    size = int(420 + 40 * k)
    cr = crest.resize((size, size), Image.LANCZOS)
    a = cr.getchannel('A').point(lambda v: int(v * k))
    cr.putalpha(a)
    c.alpha_composite(cr, ((W - size) // 2, 520 - (size - 420) // 2))
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k2 = ease_out((t - 0.35) / 0.6)
    text_center(d, 1030 + (1 - k2) * 40, 'LİG MASASI', F_HEAD_BIG, WHITE, int(255 * k2))
    k3 = ease_out((t - 0.75) / 0.6)
    text_center(d, 1215 + (1 - k3) * 30, 'Amatör turnuvanın dijital masası', F_SUB, GOLD, int(255 * k3))
    return Image.alpha_composite(c, layer)


def screen_scene(shots, title, sub):
    """shots: [(phone_img, start_s)]; aynı başlık altında sırayla değişir."""
    def render(t, dur):
        c = BG.copy()
        c = headline(c, title, sub, t)
        idx = max(i for i, (_, s) in enumerate(shots) if t >= s)
        ph, s = shots[idx]
        if idx == 0:
            return place_phone(c, ph, t, dur)
        # Sonraki ekrana yumuşak geçiş (telefon yerinde kalır).
        prev = shots[idx - 1][0]
        c2 = place_phone(c.copy(), prev, t, dur, enter=False)
        c3 = place_phone(c.copy(), ph, t, dur, enter=False)
        k = ease_in_out((t - s) / 0.3)
        return Image.blend(c2, c3, k)
    return render


def kulube_card(t, dur):
    c = BG.copy()
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k = ease_out(t / 0.5)
    # Turuncu Kulübe rozeti (uygulamadaki kartın rengi).
    bw, bh = 560, 230
    y = 720 + (1 - k) * 60
    d.rounded_rectangle([(W - bw) / 2, y, (W + bw) / 2, y + bh], 40,
                        fill=(217, 119, 6, int(255 * k)))
    text_center(d, y + 30, 'KULÜBE', F_HEAD_BIG, WHITE, int(255 * k))
    k2 = ease_out((t - 0.3) / 0.5)
    text_center(d, 1010 + (1 - k2) * 30, 'Maçı tek ekrandan yönet', F_HEAD, WHITE, int(255 * k2))
    k3 = ease_out((t - 0.55) / 0.5)
    text_center(d, 1140 + (1 - k3) * 30, 'Takım ve turnuva sorumluları için', F_SUB, MUTED, int(255 * k3))
    return Image.alpha_composite(c, layer)


def outro(t, dur):
    c = BG.copy()
    k = ease_out(t / 0.7)
    size = 330
    cr = crest.resize((size, size), Image.LANCZOS)
    cr.putalpha(cr.getchannel('A').point(lambda v: int(v * k)))
    c.alpha_composite(cr, ((W - size) // 2, 400))
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k2 = ease_out((t - 0.3) / 0.6)
    text_center(d, 800 + (1 - k2) * 40, 'ÇOK YAKINDA', F_HEAD_BIG, WHITE, int(255 * k2))
    k3 = ease_out((t - 0.6) / 0.6)
    a3 = int(255 * k3)
    # İki mağaza "kapsülü" (resmi rozet değil).
    labels = ['App Store', 'Google Play']
    pw, ph_, gap = 380, 110, 40
    x = (W - (2 * pw + gap)) / 2
    y = 1010 + (1 - k3) * 30
    for i, lab in enumerate(labels):
        xx = x + i * (pw + gap)
        d.rounded_rectangle([xx, y, xx + pw, y + ph_], 55, outline=WHITE + (a3,), width=4,
                            fill=(255, 255, 255, int(18 * k3)))
        tw = d.textlength(lab, font=F_SUB)
        d.text((xx + (pw - tw) / 2, y + 30), lab, font=F_SUB, fill=WHITE + (a3,))
    k4 = ease_out((t - 0.9) / 0.6)
    a4 = int(255 * k4)
    text_center(d, 1200, 'ligmasasi.com', font('Barlow-Bold.ttf', 56), GOLD, a4)
    text_center(d, 1285, '@ligmasasi', F_SMALL, MUTED, a4)
    return Image.alpha_composite(c, layer)


def build_scenes():
    s = {n: load_screen(n) for n in (32, 45, 44, 43, 40, 38, 36, 37, 34, 33, 5)}
    s[45] = fix_home(s[45])
    s[33] = fix_stream(s[33])
    P = {n: phone(img) for n, img in s.items()}
    return [
        (2.6, intro),
        (2.3, screen_scene([(P[32], 0)], 'SAHA · KULÜBE · TRİBÜN',
                           'Futbolcu, yönetici ve taraftar tek uygulamada')),
        (2.4, screen_scene([(P[45], 0)], 'TURNUVAN CEBİNDE',
                           'Fikstür, sonuçlar ve son dakika haberleri')),
        (2.2, screen_scene([(P[44], 0)], 'KRALLIK YARIŞI',
                           'Gol ve asist krallığı her maçtan sonra güncel')),
        (2.4, screen_scene([(P[43], 0)], 'DAKİKA DAKİKA MAÇ',
                           'Goller, kartlar, oyuncu değişiklikleri')),
        (2.2, screen_scene([(P[40], 0)], 'DİZİLİŞ VE KADROLAR',
                           'Sahadaki 11, forma numaralarıyla')),
        (1.8, kulube_card),
        (2.0, screen_scene([(P[38], 0)], 'HIZLI SKOR',
                           'Sonucu saniyeler içinde gir')),
        (3.0, screen_scene([(P[36], 0), (P[37], 1.0), (P[34], 2.0)], 'TÜM MAÇ OLAYLARI',
                           'Gol, penaltı, kart, değişiklik, maçın adamı')),
        (2.2, screen_scene([(P[33], 0)], 'MAÇ YAYINI',
                           'Canlı yayın bağlantısı maç sayfasında')),
        (2.2, screen_scene([(P[5], 0)], 'OYUNCU PROFİLİ',
                           'Her futbolcunun istatistiği tek kartta')),
        (3.4, outro),
    ]


def main():
    os.makedirs(OUT, exist_ok=True)
    scenes = build_scenes()
    if STILLS:
        for i, (dur, fn) in enumerate(scenes):
            fn(dur * 0.8, dur).convert('RGB').save(f'{OUT}/still_{i:02d}.jpg', quality=88)
        return
    n = 0
    for dur, fn in scenes:
        frames = round(dur * FPS)
        for f in range(frames):
            fn(f / FPS, dur).convert('RGB').save(f'{OUT}/f_{n:05d}.jpg', quality=92)
            n += 1
    print('frames', n)


if __name__ == '__main__':
    main()
