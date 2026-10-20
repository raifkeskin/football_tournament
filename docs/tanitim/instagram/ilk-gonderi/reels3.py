"""Üç kısa Reels (Tribün / Saha / Kulübe), resmi mağaza rozetleriyle.

Kullanım: python reels3.py <images_dir> <out_dir> [--stills]
"""
import os
import sys

from PIL import Image, ImageDraw

import reel
from reel import (W, H, FPS, WHITE, MUTED, GOLD, F_HEAD_BIG, F_SUB, F_SMALL,
                  ease_out, text_center, font, phone, screen_scene, fix_stream,
                  load_screen, crest)

OUT = sys.argv[2]
STILLS = '--stills' in sys.argv
BADGES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'badges')

# Web'den (tarayıcıdan) çekilen yeni ekranlar: adres çubuğu ve alt çubuk kırpılır.
WEB_CROP = (0, 206, 945, 1888)

THEMES = {
    # rol: (arka plan üst rengi, rozet rengi, başlık, alt yazı)
    'tribun': ((23, 37, 84), (30, 58, 138), 'TRİBÜN', 'Turnuvan cebinde'),
    'saha': ((11, 61, 36), (22, 163, 74), 'SAHA', 'Her maç kayıt altında'),
    'kulube': ((84, 45, 8), (217, 119, 6), 'KULÜBE', 'Maçı tek ekrandan yönet'),
}


def badge_images():
    a = Image.open(os.path.join(BADGES, 'apple_en.png')).convert('RGBA')
    g = Image.open(os.path.join(BADGES, 'google_en.png')).convert('RGBA')
    g = g.crop(g.getbbox())  # Google rozetindeki saydam kenar boşluğu
    h = 112
    a = a.resize((round(a.width * h / a.height), h), Image.LANCZOS)
    g = g.resize((round(g.width * h / g.height), h), Image.LANCZOS)
    return a, g


APPLE, GOOGLE = badge_images()


def fade(img, k):
    img = img.copy()
    img.putalpha(img.getchannel('A').point(lambda v: int(v * k)))
    return img


def make_intro(theme):
    _, pill, title, sub = theme

    def render(t, dur):
        c = reel.BG.copy()
        k = ease_out(t / 0.6)
        size = 360
        c.alpha_composite(fade(crest.resize((size, size), Image.LANCZOS), k),
                          ((W - size) // 2, 470))
        layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        k2 = ease_out((t - 0.2) / 0.5)
        text_center(d, 880 + (1 - k2) * 30, 'LİG MASASI', font('BarlowCondensed-ExtraBoldItalic.ttf', 120),
                    WHITE, int(255 * k2))
        # Rol rozeti (giriş ekranındaki kartın rengi).
        k3 = ease_out((t - 0.4) / 0.5)
        f = font('BarlowCondensed-ExtraBoldItalic.ttf', 96)
        tw = d.textlength(title, font=f)
        bw, bh = tw + 120, 150
        y = 1060 + (1 - k3) * 40
        d.rounded_rectangle([(W - bw) / 2, y, (W + bw) / 2, y + bh], 36, fill=pill + (int(255 * k3),))
        text_center(d, y + 18, title, f, WHITE, int(255 * k3))
        k4 = ease_out((t - 0.6) / 0.5)
        text_center(d, 1250 + (1 - k4) * 30, sub, font('Barlow-SemiBold.ttf', 50), WHITE, int(255 * k4))
        return Image.alpha_composite(c, layer)
    return render


def outro(t, dur):
    c = reel.BG.copy()
    k = ease_out(t / 0.6)
    size = 300
    c.alpha_composite(fade(crest.resize((size, size), Image.LANCZOS), k), ((W - size) // 2, 440))
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k2 = ease_out((t - 0.2) / 0.5)
    text_center(d, 800 + (1 - k2) * 40, 'ÇOK YAKINDA', F_HEAD_BIG, WHITE, int(255 * k2))
    k3 = ease_out((t - 0.45) / 0.5)
    gap = 36
    total = APPLE.width + GOOGLE.width + gap
    x = (W - total) // 2
    y = round(1010 + (1 - k3) * 30)
    c = Image.alpha_composite(c, layer)
    c.alpha_composite(fade(APPLE, k3), (x, y))
    c.alpha_composite(fade(GOOGLE, k3), (x + APPLE.width + gap, y))
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k4 = ease_out((t - 0.7) / 0.5)
    a4 = int(255 * k4)
    text_center(d, 1200, 'ligmasasi.com', font('Barlow-Bold.ttf', 56), GOLD, a4)
    text_center(d, 1285, '@ligmasasi', F_SMALL, MUTED, a4)
    return Image.alpha_composite(c, layer)


def cut_rows(img, a, b, fill=(15, 23, 42)):
    """[a, b) satırlarını çıkarır, alttakileri yukarı kaydırır."""
    top = img.crop((0, 0, img.width, a))
    rest = img.crop((0, b, img.width, img.height))
    out = Image.new('RGB', img.size, fill)
    out.paste(top, (0, 0))
    out.paste(rest, (0, a))
    return out


def build():
    s = {n: load_screen(n) for n in (46, 47, 48, 49, 43, 40, 33, 5, 38, 36, 37, 35, 34, 42)}
    # 46: yöneticiye özel kart cezası satırı çıkarılır (alt kırpma payı korunur).
    s[46] = cut_rows(s[46], 1055, 1252)
    s[33] = fix_stream(s[33])
    P = {}
    for n, img in s.items():
        if n in (46, 47, 48):
            crop = (WEB_CROP[0], WEB_CROP[1], WEB_CROP[2], WEB_CROP[3] - (197 if n == 46 else 0))
            P[n] = phone(img, crop)
        elif n == 49:
            P[n] = phone(img, None)
        else:
            P[n] = phone(img)
    sc = screen_scene
    return {
        'tribun': [
            (1.9, make_intro(THEMES['tribun'])),
            (2.4, sc([(P[46], 0)], 'TURNUVAN CEBİNDE', 'Bu haftanın maçları ve son dakika haberleri')),
            (2.4, sc([(P[49], 0)], 'PUAN DURUMU', 'Averaj ve form otomatik hesaplanır')),
            (2.8, sc([(P[47], 0), (P[48], 1.4)], 'KRALLIK YARIŞI', 'Gol ve asist krallığı, geçen haftanın sonuçları')),
            (2.8, outro),
        ],
        'saha': [
            (1.9, make_intro(THEMES['saha'])),
            (2.3, sc([(P[43], 0)], 'DAKİKA DAKİKA MAÇ', 'Goller, kartlar, oyuncu değişiklikleri')),
            (2.1, sc([(P[40], 0)], 'DİZİLİŞ', 'Sahadaki 11, forma numaralarıyla')),
            (2.1, sc([(P[33], 0)], 'MAÇ YAYINI', 'Canlı yayın bağlantısı maç sayfasında')),
            (2.3, sc([(P[5], 0)], 'OYUNCU PROFİLİ', 'Her futbolcunun istatistiği tek kartta')),
            (2.8, outro),
        ],
        'kulube': [
            (1.9, make_intro(THEMES['kulube'])),
            (2.1, sc([(P[38], 0)], 'HIZLI SKOR', 'Sonucu saniyeler içinde gir')),
            (3.6, sc([(P[36], 0), (P[37], 0.9), (P[35], 1.8), (P[34], 2.7)], 'TÜM MAÇ OLAYLARI',
                     'Gol, penaltı, kart, değişiklik, maçın adamı')),
            (2.2, sc([(P[42], 0)], 'KADRO VE ESAME', 'Maç kadrosunu gir, tek dokunuşla paylaş')),
            (2.8, outro),
        ],
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    reels = build()
    for name, scenes in reels.items():
        reel.BG = reel.make_background(THEMES[name][0])
        if STILLS:
            for i, (dur, fn) in enumerate(scenes):
                fn(dur * 0.85, dur).convert('RGB').save(f'{OUT}/{name}_{i}.jpg', quality=88)
            continue
        d = f'{OUT}/{name}'
        os.makedirs(d, exist_ok=True)
        n = 0
        for dur, fn in scenes:
            for f in range(round(dur * FPS)):
                fn(f / FPS, dur).convert('RGB').save(f'{d}/f_{n:05d}.jpg', quality=92)
                n += 1
        # Kapak: tanıtım sahnesinin son hâli (profil ızgarasında 3:4 ortası görünür).
        dur, fn = scenes[0]
        fn(dur, dur).convert('RGB').save(f'{OUT}/{name}_kapak.jpg', quality=92)
        print(name, n, 'kare')


if __name__ == '__main__':
    main()
