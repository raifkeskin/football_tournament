"""ligmasasi.com/indir bağlantı önizleme görseli (og:image, 1200x630).

WhatsApp/Telegram/Instagram DM bağlantıyı bu görselle geniş kart olarak gösterir.
Kullanım: python og_indir.py   →  web/og-indir.jpg   (Pillow)
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'instagram', 'reels'))
import lm_outro  # noqa: E402
from lm_outro import APPLE, GOOGLE, CREST, GOLD, WHITE, MUTED, font  # noqa: E402

W, H = 1200, 630
OUT = os.path.join(HERE, '..', '..', '..', 'web', 'og-indir.jpg')
HEAD = 'BarlowCondensed-ExtraBoldItalic.ttf'


def main():
    bg = lm_outro.BG
    c = bg.crop((0, 0, bg.width, round(bg.width * H / W))).resize((W, H), Image.LANCZOS)
    crest = Image.open(CREST).convert('RGBA').resize((360, 360), Image.LANCZOS)
    c.alpha_composite(crest, (70, (H - 360) // 2))
    d = ImageDraw.Draw(c)
    x = 490
    d.text((x, 92), 'LİG MASASI', font=font(HEAD, 132), fill=WHITE)
    d.text((x + 4, 250), 'Amatör turnuvalar için lig yönetimi', font=font('Barlow-Bold.ttf', 38),
           fill=GOLD)
    d.text((x + 4, 306), 'Canlı skor • Puan durumu • Kadro • Bildirimler',
           font=font('Barlow-Medium.ttf', 28), fill=MUTED)
    bh = 82
    y = 392
    for b in (APPLE, GOOGLE):
        b = b.resize((round(b.width * bh / b.height), bh), Image.LANCZOS)
        c.alpha_composite(b, (x, y))
        x += b.width + 24
    c.convert('RGB').save(OUT, quality=88, optimize=True)
    print(os.path.abspath(OUT), os.path.getsize(OUT))


if __name__ == '__main__':
    main()
