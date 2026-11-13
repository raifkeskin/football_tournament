"""Markete çıkış duyurusu "Artık cebinde": gönderi (1080x1350) + Reels
(1080x1920, ~18 sn).

Kullanım: python markette.py <out_dir> [--stills]
Ekranlar: ~/Desktop/LigMasasi-AppStore/1.0.5 (iphone63_*, Champions verisi) ve
bu klasördeki ekran_haber.png (gerçek maç sonucu haberi, durum çubuğu 9:41).
Müzik yok; Instagram'da eklenir.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'reels'))
import lm_outro  # noqa: E402
from lm_outro import (APPLE, GOOGLE, CREST, GOLD, WHITE, MUTED, ease_out,  # noqa: E402
                      font, outro_frame)

SHOTS = '/Users/raifkeskin/Desktop/LigMasasi-AppStore/1.0.5'
HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 30
HEAD = 'BarlowCondensed-ExtraBoldItalic.ttf'


def background(w, h):
    """lm_outro arka planı, istenen boya kırpılır (üst kısım korunur)."""
    return lm_outro.BG.copy().crop((0, 0, w, h)) if h <= lm_outro.H else \
        lm_outro.BG.resize((w, h))


def phone(name, height):
    """Ekran görüntüsü + koyu çerçeve + yuvarlak köşe + gölge (RGBA)."""
    path = name if os.path.isabs(name) else os.path.join(SHOTS, name)
    shot = Image.open(path).convert('RGBA')
    sw = round(shot.width * height / shot.height)
    shot = shot.resize((sw, height), Image.LANCZOS)
    pad, r = max(8, height // 70), height // 16
    W, H = sw + pad * 2, height + pad * 2
    body = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, W - 1, H - 1], r + pad, fill=(14, 18, 28, 255),
                                           outline=(70, 80, 100, 255), width=3)
    mask = Image.new('L', (sw, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, height - 1], r, fill=255)
    body.paste(shot, (pad, pad), mask)
    m = 60
    out = Image.new('RGBA', (W + m * 2, H + m * 2), (0, 0, 0, 0))
    sh = Image.new('RGBA', out.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([m, m + 20, m + W, m + H + 20], r + pad, fill=(0, 0, 0, 150))
    out = Image.alpha_composite(out, sh.filter(ImageFilter.GaussianBlur(28)))
    out.alpha_composite(body, (m, m))
    return out


def center(d, w, y, s, f, fill):
    d.text(((w - d.textlength(s, font=f)) / 2, y), s, font=f, fill=fill)


def badges(c, y, gap=36):
    x = (c.width - (APPLE.width + GOOGLE.width + gap)) // 2
    c.alpha_composite(APPLE, (x, y))
    c.alpha_composite(GOOGLE, (x + APPLE.width + gap, y))


# ---------------------------------------------------------------- gönderi

def post():
    W, H = 1080, 1350
    c = background(W, H)
    crest = Image.open(CREST).convert('RGBA').resize((150, 150), Image.LANCZOS)
    c.alpha_composite(crest, ((W - 150) // 2, 48))
    d = ImageDraw.Draw(c)
    center(d, W, 210, 'LİG MASASI', font(HEAD, 120), WHITE)
    center(d, W, 345, 'ARTIK CEBİNDE!', font(HEAD, 96), GOLD)
    # Üç telefon: ortada ana sayfa, yanlarda canlı maç ve puan (hafif eğik).
    side_h, mid_h = 640, 720
    for name, dx, ang in (('iphone63_2.png', -300, 7), ('iphone63_6.png', 300, -7)):
        p = phone(name, side_h).rotate(ang, resample=Image.BICUBIC, expand=True)
        c.alpha_composite(p, (W // 2 + dx - p.width // 2, 500))
    p = phone('iphone63_1.png', mid_h)
    c.alpha_composite(p, ((W - p.width) // 2, 440))
    # Alt bant: rozetler + link (telefonların üstüne koyu degrade).
    fade = Image.new('RGBA', (W, 330), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fade)
    for i in range(330):
        fd.line([0, i, W, i], fill=(8, 12, 24, min(255, int(255 * (i / 150)))))
    c.alpha_composite(fade, (0, H - 330))
    # Link yazılmaz: bağlantı profil linki / hikâye çıkartmasıyla verilir.
    badges(c, H - 175)
    return c.convert('RGB')


# ---------------------------------------------------------------- reels

W, H = 1080, 1920
SCENES = [
    ('iphone63_1.png', 'Sıradaki maçın, takımın, ligin'),
    ('iphone63_2.png', 'Canlı skor, dakika dakika'),
    ('iphone63_6.png', 'Canlı puan durumu'),
    ('iphone63_7.png', 'Diziliş ve kadro'),
    (os.path.join(HERE, 'ekran_haber.png'), 'Maç sonu haberleri'),
    ('iphone63_10.png', 'Tek dokunuşla paylaş'),
]
T_INTRO, T_SHOT, T_OUTRO = 3.0, 1.8, 3.6
BG_R = background(W, H)
CREST_R = Image.open(CREST).convert('RGBA').resize((300, 300), Image.LANCZOS)
PHONES = [phone(n, 1300) for n, _ in SCENES]


def fade(img, k):
    img = img.copy()
    img.putalpha(img.getchannel('A').point(lambda v: int(v * k)))
    return img


def intro(t):
    c = BG_R.copy()
    k = ease_out(t / 0.6)
    c.alpha_composite(fade(CREST_R, k), ((W - 300) // 2, 380 + round((1 - k) * 30)))
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k2 = ease_out((t - 0.3) / 0.5)
    a = int(255 * k2)
    center(d, W, 760 + (1 - k2) * 30, 'BEKLENEN AN GELDİ', font(HEAD, 110), WHITE + (a,))
    k3 = ease_out((t - 0.8) / 0.5)
    center(d, W, 900 + (1 - k3) * 30, 'LİG MASASI', font(HEAD, 190), WHITE + (int(255 * k3),))
    center(d, W, 1120 + (1 - k3) * 30, 'ARTIK CEBİNDE', font(HEAD, 130), GOLD + (int(255 * k3),))
    c = Image.alpha_composite(c, layer)
    k4 = ease_out((t - 1.4) / 0.5)
    gap = 36
    x = (W - (APPLE.width + GOOGLE.width + gap)) // 2
    y = round(1340 + (1 - k4) * 30)
    c.alpha_composite(fade(APPLE, k4), (x, y))
    c.alpha_composite(fade(GOOGLE, k4), (x + APPLE.width + gap, y))
    return c.convert('RGB')


def shots(t):
    i = min(int(t / T_SHOT), len(SCENES) - 1)
    lt = t - i * T_SHOT
    c = BG_R.copy()
    d = ImageDraw.Draw(c)
    center(d, W, 120, 'LİG MASASI', font(HEAD, 92), GOLD)
    k = ease_out(lt / 0.35)
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    center(ld, W, 250 + (1 - k) * 20, SCENES[i][1], font('Barlow-Bold.ttf', 62), WHITE + (int(255 * k),))
    c = Image.alpha_composite(c, layer)
    p = PHONES[i]
    # Yeni ekran sağdan kayarak gelir, öncekinin üstüne.
    if i > 0 and lt < 0.45:
        prev = PHONES[i - 1]
        c.alpha_composite(prev, ((W - prev.width) // 2, 380))
        x = round((W - p.width) / 2 + (1 - ease_out(lt / 0.45)) * W)
    else:
        x = (W - p.width) // 2
        if i == 0:
            p = fade(p, ease_out(lt / 0.4))
    c.alpha_composite(p, (x, 380 + (round((1 - ease_out(lt / 0.4)) * 60) if i == 0 else 0)))
    return c.convert('RGB')


def frame(t):
    if t < T_INTRO:
        return intro(t)
    t -= T_INTRO
    if t < T_SHOT * len(SCENES):
        return shots(t)
    return outro_frame(t - T_SHOT * len(SCENES), headline='ŞİMDİ İNDİR', url='')


def reels(path):
    total = T_INTRO + T_SHOT * len(SCENES) + T_OUTRO
    n = round(total * FPS)
    proc = subprocess.Popen(
        ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
         '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-', '-f', 'lavfi', '-i',
         'anullsrc=channel_layout=stereo:sample_rate=44100', '-shortest',
         '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'medium', '-crf', '18',
         '-c:a', 'aac', '-movflags', '+faststart', path], stdin=subprocess.PIPE)
    for f in range(n):
        proc.stdin.write(frame(f / FPS).tobytes())
    proc.stdin.close()
    proc.wait()


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    post().save(os.path.join(out, 'gonderi_markette.jpg'), quality=92)
    if '--stills' in sys.argv:
        for t in (2.5, 3.9, 9.6, 11.5, 13.2, 16.0):
            frame(t).save(os.path.join(out, f'kare_{t:04.1f}.jpg'), quality=85)
    else:
        frame(2.9).save(os.path.join(out, 'reels_kapak.jpg'), quality=92)
        reels(os.path.join(out, 'reels_markette.mp4'))
