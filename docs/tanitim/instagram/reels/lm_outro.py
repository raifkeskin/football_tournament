"""Lig Masası tanıtım videolarının ortak bitiş kartı (1080x1920).

Markete çıkana kadar tüm Reels/görseller bununla biter: arma, LİG MASASI,
"Amatör turnuvalar için lig yönetimi", türler, ÇOK YAKINDA, resmi App Store /
Google Play rozetleri ve ligmasasi.com (bkz. ilk-gonderi/reels3.py outro).

Kullanım: from lm_outro import outro_frame; img = outro_frame(t)  # t: saniye
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = '/Users/raifkeskin/football_tournament'
FONTS = ROOT + '/assets/fonts/'
BADGES = ROOT + '/docs/tanitim/instagram/ilk-gonderi/rozetler'
CREST = ROOT + '/design/logo-lm/lm-arma-yuvarlak-1024.png'

W, H = 1080, 1920
GOLD = (224, 165, 38)
WHITE = (255, 255, 255)
MUTED = (176, 190, 206)


def font(name, size):
    return ImageFont.truetype(FONTS + name, size)


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def _background(top=(11, 61, 36)):
    """Yeşilden laciverte degrade, silik saha çizgileri, üstte altın parıltı."""
    mid, bot = (15, 23, 42), (8, 12, 24)
    col = Image.new('RGB', (1, H))
    px = col.load()
    for y in range(H):
        t = y / H
        if t < 0.45:
            k, a, b = t / 0.45, top, mid
        else:
            k, a, b = (t - 0.45) / 0.55, mid, bot
        px[0, y] = tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))
    bg = col.resize((W, H)).convert('RGBA')
    lines = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lines)
    a = (255, 255, 255, 14)
    d.ellipse([W / 2 - 300, H / 2 - 300, W / 2 + 300, H / 2 + 300], outline=a, width=4)
    d.line([0, H / 2, W, H / 2], fill=a, width=4)
    d.rectangle([W / 2 - 330, -10, W / 2 + 330, 330], outline=a, width=4)
    d.rectangle([W / 2 - 330, H - 330, W / 2 + 330, H + 10], outline=a, width=4)
    bg = Image.alpha_composite(bg, lines)
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-200, -500, W + 200, 500], fill=(224, 165, 38, 30))
    return Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(160)))


def _badges(h=112):
    a = Image.open(os.path.join(BADGES, 'apple_en.png')).convert('RGBA')
    g = Image.open(os.path.join(BADGES, 'google_en.png')).convert('RGBA')
    g = g.crop(g.getbbox())  # Google rozetindeki saydam kenar boşluğu
    a = a.resize((round(a.width * h / a.height), h), Image.LANCZOS)
    g = g.resize((round(g.width * h / g.height), h), Image.LANCZOS)
    return a, g


BG = _background()
APPLE, GOOGLE = _badges()
CREST_IMG = Image.open(CREST).convert('RGBA').resize((330, 330), Image.LANCZOS)


def _fade(img, k):
    img = img.copy()
    img.putalpha(img.getchannel('A').point(lambda v: int(v * k)))
    return img


def _center(d, y, s, f, fill, alpha):
    w = d.textlength(s, font=f)
    d.text(((W - w) / 2, y), s, font=f, fill=fill + (alpha,))


def outro_frame(t):
    """t saniyedeki bitiş karesi (RGB). Öğeler sırayla belirir (~1.4 sn)."""
    c = BG.copy()
    k = ease_out(t / 0.6)
    c.alpha_composite(_fade(CREST_IMG, k), ((W - CREST_IMG.width) // 2, 330 + round((1 - k) * 30)))
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k2 = ease_out((t - 0.2) / 0.5)
    a2 = int(255 * k2)
    _center(d, 720 + (1 - k2) * 30, 'LİG MASASI', font('BarlowCondensed-ExtraBoldItalic.ttf', 176), WHITE, a2)
    _center(d, 925, 'Amatör turnuvalar için lig yönetimi', font('Barlow-SemiBold.ttf', 52), GOLD, a2)
    _center(d, 1002, 'Veteran • Halısaha • Okul • Şirket', font('Barlow-Medium.ttf', 44), MUTED, a2)
    d.line([W / 2 - 150, 1100, W / 2 + 150, 1100], fill=WHITE + (int(220 * k2),), width=4)
    k3 = ease_out((t - 0.45) / 0.5)
    _center(d, 1140 + (1 - k3) * 30, 'ÇOK YAKINDA', font('BarlowCondensed-ExtraBoldItalic.ttf', 150),
            WHITE, int(255 * k3))
    c = Image.alpha_composite(c, layer)
    k4 = ease_out((t - 0.7) / 0.5)
    gap = 36
    x = (W - (APPLE.width + GOOGLE.width + gap)) // 2
    y = round(1345 + (1 - k4) * 30)
    c.alpha_composite(_fade(APPLE, k4), (x, y))
    c.alpha_composite(_fade(GOOGLE, k4), (x + APPLE.width + gap, y))
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    k5 = ease_out((t - 0.95) / 0.5)
    _center(d, 1500, 'ligmasasi.com', font('Barlow-Bold.ttf', 64), GOLD, int(255 * k5))
    return Image.alpha_composite(c, layer).convert('RGB')


if __name__ == '__main__':
    outro_frame(3.0).save('/tmp/lm_outro_preview.png')
