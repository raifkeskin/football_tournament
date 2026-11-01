"""Futbolcu kaydı rehberi Reels'i (1080x1920, sessiz; müzik Instagram'da eklenir).

WhatsApp rehberinin 8 karesi (docs/tanitim/whatsapp/futbolcu-kaydi) sırayla,
kaydırma geçişiyle gösterilir; üstte hikâye tarzı ilerleme çubuğu, sonda
"ŞİMDİ İNDİR" bitiş kartı.

Kullanım: python futbolcu_kaydi_reels.py [out_dir] [--stills]   (Pillow + ffmpeg)
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'reels'))
import lm_outro  # noqa: E402
from lm_outro import GOLD, WHITE, MUTED, ease_out, font, outro_frame  # noqa: E402

SLIDES = os.path.join(HERE, '..', '..', 'whatsapp', 'futbolcu-kaydi')
W, H = 1080, 1920
FPS = 30
# Kare başına süre: kapak kısa, adımlar okunacak kadar, son kare (sık sorulanlar) uzun.
DUR = (3.5, 5.0, 5.0, 5.5, 5.5, 5.0, 5.5, 7.0)
T_PUSH, T_OUTRO = 0.45, 3.6
CW, CH = 1000, 1250
CX, CY = (W - CW) // 2, 330


SH = 60  # gölge payı: kart, gölgesiyle birlikte kayar


def _card(path):
    im = Image.open(path).convert('RGBA').resize((CW, CH), Image.LANCZOS)
    mask = Image.new('L', (CW, CH), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, CW - 1, CH - 1], 40, fill=255)
    im.putalpha(mask)
    out = Image.new('RGBA', (CW + SH * 2, CH + SH * 2), (0, 0, 0, 0))
    ImageDraw.Draw(out).rounded_rectangle([SH, SH + 24, SH + CW, SH + CH + 24], 40,
                                          fill=(0, 0, 0, 170))
    out = out.filter(ImageFilter.GaussianBlur(30))
    out.alpha_composite(im, (SH, SH))
    return out


CARDS = [_card(os.path.join(SLIDES, f'futbolcu_kaydi_{i}.jpg')) for i in range(1, 9)]
STARTS = [sum(DUR[:i]) for i in range(len(DUR))]
T_SLIDES = sum(DUR)


def _base():
    c = lm_outro.BG.copy()
    d = ImageDraw.Draw(c)
    s = 'FUTBOLCU KAYDI'
    f = font('BarlowCondensed-ExtraBoldItalic.ttf', 60)
    d.text(((W - d.textlength(s, font=f)) / 2, 200), s, font=f, fill=WHITE)
    return c


BASE = _base()


def _put(c, card, x):
    """Kartı (gölgesiyle) yerleştirir; tuvalin dışına taşan kısım kırpılır."""
    x -= SH
    left = max(0, -x)
    if left >= card.width or x >= W:
        return
    c.alpha_composite(card, (max(0, x), CY - SH), (left, 0))


def slides(t):
    c = BASE.copy()
    i = max(k for k, s in enumerate(STARTS) if s <= t)
    local = t - STARTS[i]
    # Kaydırma: yeni kare sağdan gelir, eskisi sola çıkar (karenin ilk T_PUSH saniyesi).
    if i > 0 and local < T_PUSH:
        k = ease_out(local / T_PUSH)
        off = round((1 - k) * (W + 40))
        _put(c, CARDS[i - 1], CX + off - W - 40)
        _put(c, CARDS[i], CX + off)
    else:
        _put(c, CARDS[i], CX)
    # Hikâye tarzı ilerleme çubuğu.
    d = ImageDraw.Draw(c)
    d.draw = Image.core.draw(c.im, 1)  # yarı saydam rengi zeminle karıştır
    n, gap, x0, y0 = len(DUR), 10, 60, 150
    seg = (W - 2 * x0 - gap * (n - 1)) / n
    for k in range(n):
        x = x0 + k * (seg + gap)
        d.rounded_rectangle([x, y0, x + seg, y0 + 8], 4, fill=(255, 255, 255, 60))
        p = 1.0 if k < i else (local / DUR[i] if k == i else 0.0)
        if p > 0:
            d.rounded_rectangle([x, y0, x + max(8, seg * p), y0 + 8], 4, fill=GOLD)
    return c.convert('RGB')


def frame(t):
    if t < T_SLIDES:
        return slides(t)
    return outro_frame(t - T_SLIDES, headline='ŞİMDİ İNDİR', url='ligmasasi.com/indir')


def reels(path):
    n = round((T_SLIDES + T_OUTRO) * FPS)
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
    out = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else HERE
    os.makedirs(out, exist_ok=True)
    if '--stills' in sys.argv:
        for t in (1.0, 3.7, 12.0, T_SLIDES - 2, T_SLIDES + 2.5):
            frame(t).save(os.path.join(out, f'kare_{t:04.1f}.jpg'), quality=85)
    else:
        frame(1.0).save(os.path.join(out, 'reels_kapak.jpg'), quality=92)
        reels(os.path.join(out, 'futbolcu_kaydi_reels.mp4'))
