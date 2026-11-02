"""Futbolcu kaydı rehberi: WhatsApp'ta takım sorumlularına atılan 8 görsel
(1080x1350). Ekranlar mockup'tır (uygulamadaki metin ve renklerle çizilir).

Kullanım: python futbolcu_kaydi.py [out_dir]   (Pillow)
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'instagram', 'reels'))
import lm_outro  # noqa: E402
from lm_outro import APPLE, GOOGLE, CREST, GOLD, WHITE, MUTED, font  # noqa: E402

W, H = 1080, 1350
TOTAL = 8
STEPS = 6
HEAD = 'BarlowCondensed-ExtraBoldItalic.ttf'
XB, B, SB, M = ('Barlow-ExtraBold.ttf', 'Barlow-Bold.ttf', 'Barlow-SemiBold.ttf',
                'Barlow-Medium.ttf')
MONO = '/System/Library/Fonts/Menlo.ttc'

BG_DARK = (15, 23, 42)
CARD = (30, 41, 59)
LINE = (51, 65, 85)
ACCENT = (16, 185, 129)
BLUE = (56, 189, 248)
APP_MUTED = (148, 163, 184)
DARK_TEXT = (15, 23, 42)


# ---------------------------------------------------------------- yardımcılar

def Dr(im):
    """ImageDraw; opak RGBA görselde yarı saydam renkleri üzerine karıştırır
    (saydam katmanlara, ör. gölge ve parıltıya, düz çizer)."""
    d = ImageDraw.Draw(im)
    if im.mode == 'RGBA' and im.getpixel((0, 0))[3] == 255:
        d.draw = Image.core.draw(im.im, 1)
    return d


def wrap(d, text, f, width):
    lines = []
    for para in text.split('\n'):
        cur = ''
        for word in para.split(' '):
            t = (cur + ' ' + word).strip()
            if d.textlength(t, font=f) <= width:
                cur = t
            else:
                lines.append(cur)
                cur = word
        lines.append(cur)
    return lines


def text_block(d, xy, text, f, fill, width, lh):
    x, y = xy
    for line in wrap(d, text, f, width):
        d.text((x, y), line, font=f, fill=fill)
        y += lh
    return y


def center(d, y, s, f, fill, w=W, x0=0):
    d.text((x0 + (w - d.textlength(s, font=f)) / 2, y), s, font=f, fill=fill)


def gradient(size, c1, c2):
    w, h = size
    g = Image.new('RGBA', (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            k = (x / w + y / h) / 2
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * k) for i in range(3)) + (255,)
    return g


def grad_box(img, box, c1, c2, r):
    x0, y0, x1, y1 = [int(v) for v in box]
    g = gradient((x1 - x0, y1 - y0), c1, c2)
    mask = Image.new('L', g.size, 0)
    Dr(mask).rounded_rectangle([0, 0, g.width - 1, g.height - 1], r, fill=255)
    img.paste(g, (x0, y0), mask)


def highlight(img, box, r=22, n=None):
    """Altın çerçeve + parıltı: kullanıcının dokunacağı yer."""
    x0, y0, x1, y1 = box
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    Dr(glow).rounded_rectangle([x0 - 6, y0 - 6, x1 + 6, y1 + 6], r + 6,
                                           outline=GOLD + (200,), width=14)
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10)))
    d = Dr(img)
    d.rounded_rectangle([x0 - 5, y0 - 5, x1 + 5, y1 + 5], r + 5, outline=GOLD, width=5)
    if n is not None:
        cx, cy = x1 - 4, y0 - 4
        d.ellipse([cx - 24, cy - 24, cx + 24, cy + 24], fill=GOLD)
        f = font(XB, 28)
        d.text((cx - d.textlength(n, font=f) / 2, cy - 18), n, font=f, fill=DARK_TEXT)


def check(d, cx, cy, r, color, fg=WHITE, width=None):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    w = width or max(3, r // 4)
    d.line([(cx - r * .45, cy + r * .02), (cx - r * .1, cy + r * .38), (cx + r * .5, cy - r * .35)],
           fill=fg, width=w, joint='curve')


def pill(d, x, y, s, f, fill, fg, pad=(16, 7), r=None):
    w = d.textlength(s, font=f)
    hh = f.size + pad[1] * 2
    d.rounded_rectangle([x, y, x + w + pad[0] * 2, y + hh], r or hh // 2, fill=fill)
    d.text((x + pad[0], y + pad[1] - f.size * .12), s, font=f, fill=fg)
    return x + w + pad[0] * 2


# ---------------------------------------------------------------- telefon

def phone(sw, sh, title, content, progress=None):
    """Uygulama ekranı mockup'ı + çerçeve + gölge (RGBA)."""
    scr = Image.new('RGBA', (sw, sh), BG_DARK + (255,))
    d = Dr(scr)
    d.text((30, 16), '9:41', font=font(B, 22), fill=WHITE)
    d.rounded_rectangle([sw - 66, 21, sw - 30, 37], 4, outline=WHITE, width=2)
    d.rectangle([sw - 62, 25, sw - 40, 33], fill=WHITE)
    top = 64
    if title:
        d.line([(34, 98), (22, 86), (34, 74)], fill=WHITE, width=4, joint='curve')
        d.text((58, 70), title, font=font(B, 28), fill=WHITE)
        top = 128
    if progress:
        step = progress
        seg = (sw - 32 - 70 - 12) / 3
        for i in range(3):
            x = 16 + i * (seg + 6)
            d.rounded_rectangle([x, top, x + seg, top + 6], 3,
                                fill=BLUE if i < step else LINE)
        d.text((sw - 66, top - 9), f'{step} / 3', font=font(XB, 17), fill=APP_MUTED)
        top += 30
    content(scr, Dr(scr), top)
    pad, r = 12, 46
    fw, fh = sw + pad * 2, sh + pad * 2
    body = Image.new('RGBA', (fw, fh), (0, 0, 0, 0))
    Dr(body).rounded_rectangle([0, 0, fw - 1, fh - 1], r + pad, fill=(14, 18, 28, 255),
                                           outline=(80, 92, 114, 255), width=3)
    mask = Image.new('L', (sw, sh), 0)
    Dr(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], r, fill=255)
    body.paste(scr, (pad, pad), mask)
    m = 50
    out = Image.new('RGBA', (fw + m * 2, fh + m * 2), (0, 0, 0, 0))
    sh_ = Image.new('RGBA', out.size, (0, 0, 0, 0))
    Dr(sh_).rounded_rectangle([m, m + 18, m + fw, m + fh + 18], r, fill=(0, 0, 0, 160))
    out = Image.alpha_composite(out, sh_.filter(ImageFilter.GaussianBlur(24)))
    out.alpha_composite(body, (m, m))
    return out


def card(d, box, r=20):
    d.rounded_rectangle(box, r, fill=CARD, outline=(255, 255, 255, 22), width=2)


def button(d, box, label, color=ACCENT, fg=WHITE, size=22):
    d.rounded_rectangle(box, 16, fill=color)
    f = font(XB, size)
    x0, y0, x1, y1 = box
    d.text(((x0 + x1 - d.textlength(label, font=f)) / 2, (y0 + y1) / 2 - size * .62), label,
           font=f, fill=fg)


def field(d, box, label, value, value_fill=WHITE, r=16):
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, r, fill=(255, 255, 255, 10), outline=LINE, width=2)
    d.text((x0 + 18, y0 + 10), label, font=font(SB, 16), fill=APP_MUTED)
    d.text((x0 + 18, y0 + 32), value, font=font(B, 23), fill=value_fill)


def chips(d, x, y, items, sel, maxw, size=18):
    f = font(B, size)
    cx, cy = x, y
    for s in items:
        w = d.textlength(s, font=f) + 30
        if cx + w > x + maxw:
            cx, cy = x, cy + size + 26
        on = s == sel
        d.rounded_rectangle([cx, cy, cx + w, cy + size + 16], 12,
                            fill=ACCENT if on else (255, 255, 255, 12),
                            outline=ACCENT if on else LINE, width=2)
        d.text((cx + 15, cy + 6), s, font=f, fill=WHITE if on else (203, 213, 225))
        cx += w + 8
    return cy + size + 16


# ---------------------------------------------------------------- ekranlar

def scr_login(img, d, top):
    sw = img.width
    crest = Image.open(CREST).convert('RGBA').resize((92, 92), Image.LANCZOS)
    img.alpha_composite(crest, ((sw - 92) // 2, top))
    center(d, top + 98, 'LİG MASASI', font(HEAD, 40), WHITE, w=sw)
    y = top + 160
    cw = (sw - 32 - 10) / 2
    for i, (t, s, c1, c2) in enumerate((('Saha', 'Futbolcuyum', (34, 197, 94), (15, 107, 53)),
                                        ('Kulübe', 'Turnuva / Takım\nSorumlusuyum',
                                         (245, 158, 11), (154, 91, 6)))):
        x = 16 + i * (cw + 10)
        grad_box(img, (x, y, x + cw, y + 140), c1, c2, 20)
        d.text((x + 18, y + 54), t, font=font(XB, 30), fill=WHITE)
        text_block(d, (x + 18, y + 90), s, font(SB, 15), (255, 255, 255, 220), cw - 30, 18)
    y += 152
    for t, s, c1, c2 in (('Tribün', 'Misafir girişi yaparak, tüm turnuvaları takip et',
                          (30, 58, 138), (23, 37, 84)),
                         ('Kayıt Ol', 'Hesabın yok mu? Telefonunla hesap aç',
                          (71, 85, 105), (30, 41, 59))):
        grad_box(img, (16, y, sw - 16, y + 84), c1, c2, 20)
        d.ellipse([32, y + 18, 80, y + 66], fill=(255, 255, 255, 40))
        d.text((96, y + 14), t, font=font(XB, 26), fill=WHITE)
        d.text((96, y + 48), s, font=font(SB, 15), fill=(255, 255, 255, 210))
        if t == 'Kayıt Ol':
            # kişi + artı simgesi
            d.ellipse([48, y + 26, 62, y + 40], fill=WHITE)
            d.pieslice([41, y + 41, 69, y + 66], 180, 360, fill=WHITE)
            highlight(img, (16, y, sw - 16, y + 84), 20)
            d = Dr(img)
        y += 96
    text_block(d, (22, y + 4), 'Takımına kayıtlı telefon numaranla gir; maçların ve '
               'istatistiklerin seni bekliyor.', font(M, 16), APP_MUTED, sw - 44, 21)
    y += 58
    field(d, (16, y, sw - 16, y + 72), 'Telefon Numarası', '0 (5__) ___ __ __', APP_MUTED)
    y += 84
    field(d, (16, y, sw - 16, y + 72), 'Şifre', '••••••', APP_MUTED)
    y += 86
    button(d, (16, y, sw - 16, y + 60), 'GİRİŞ YAP')


def scr_choice(img, d, top):
    sw = img.width
    d.text((20, top), 'Hangi hesabı açıyorsun?', font=font(XB, 30), fill=WHITE)
    d.text((20, top + 44), 'Seçimine göre birkaç adımda hesabın hazır olur.', font=font(M, 17),
           fill=APP_MUTED)
    y = top + 92
    grad_box(img, (16, y, sw - 16, y + 330), (22, 163, 74), (15, 107, 53), 22)
    d.ellipse([34, y + 22, 94, y + 82], fill=(255, 255, 255, 46))
    d.ellipse([54, y + 34, 74, y + 54], fill=WHITE)
    d.pieslice([44, y + 56, 84, y + 92], 180, 360, fill=WHITE)
    d.text((110, y + 34), 'Futbolcu Profili', font=font(XB, 27), fill=WHITE)
    check(d, sw - 50, y + 52, 15, BLUE)
    text_block(d, (34, y + 104), 'Kimliğini telefonuna okut; adın, soyadın ve doğum tarihin '
               'kimlikten otomatik gelir. TC Kimlik No geri dönülemez şekilde şifrelenir, '
               'bunlar dışındaki hiçbir bilgi sisteme kaydedilmez.', font(M, 17),
               (255, 255, 255, 235), sw - 76, 23)
    x = 34
    for t in ('Kimlik kartı gerekli', "NFC'li telefon"):
        x = pill(d, x, y + 278, t, font(B, 15), (0, 0, 0, 60), WHITE) + 8
    highlight(img, (16, y, sw - 16, y + 330), 22)
    d = Dr(img)
    y += 350
    grad_box(img, (16, y, sw - 16, y + 190), (245, 158, 11), (154, 91, 6), 22)
    d.ellipse([34, y + 22, 94, y + 82], fill=(255, 255, 255, 46))
    d.text((110, y + 34), 'Turnuva Kurucu /', font=font(XB, 24), fill=WHITE)
    d.text((110, y + 62), 'Sorumlusu', font=font(XB, 24), fill=WHITE)
    text_block(d, (34, y + 104), "Turnuvanı Lig Masası'nda kurmak için talep oluştur; seninle "
               'iletişime geçip kurulumu birlikte yapalım.', font(M, 17),
               (255, 255, 255, 235), sw - 76, 23)


def id_back(w, h):
    """Kimlik kartının arka yüzü: üstte şerit, altta 3 satır MRZ."""
    c = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    grad_box(c, (0, 0, w, h), (232, 238, 246), (205, 216, 232), int(h * .07))
    d = Dr(c)
    for i in range(4):
        d.rounded_rectangle([w * .06, h * (.1 + i * .09), w * (.55 - i * .06), h * (.14 + i * .09)],
                            3, fill=(150, 163, 184))
    d.rounded_rectangle([w * .66, h * .08, w * .94, h * .46], 6, fill=(175, 188, 206))
    d.rectangle([0, h * .55, w, h], fill=(244, 246, 250))
    f = font(MONO, int(h * .085))
    for i, s in enumerate(('I<TURA12B345678<<<<<<<<<<<', '9001012M3012317TUR<<<<<<<4',
                           'YILMAZ<<MEHMET<<<<<<<<<<<<')):
        d.text((w * .05, h * (.6 + i * .12)), s, font=f, fill=(30, 41, 59))
    return c


def scr_mrz(img, d, top):
    sw, sh = img.size
    d.rectangle([0, top - 10, sw, sh], fill=(4, 7, 14))
    d.text((24, top + 8), 'Kimliğin arka yüzünü', font=font(XB, 25), fill=WHITE)
    d.text((24, top + 40), 'çerçeveye hizalayın', font=font(XB, 25), fill=WHITE)
    cw, ch = sw - 70, int((sw - 70) / 1.585)
    x, y = 35, top + 120
    card_img = id_back(cw, ch).rotate(-3, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(card_img, (x - 6, y - 6))
    d = Dr(img)
    L = 46
    for (px, py, dx, dy) in ((x - 14, y - 14, 1, 1), (x + cw + 14, y - 14, -1, 1),
                             (x - 14, y + ch + 14, 1, -1), (x + cw + 14, y + ch + 14, -1, -1)):
        d.line([(px, py + dy * L), (px, py), (px + dx * L, py)], fill=ACCENT, width=6)
    d.rounded_rectangle([x, y + ch * .56, x + cw, y + ch], 8, outline=GOLD, width=4)
    pill(d, x + 10, y + ch + 26, 'Bu 3 satır okunur', font(B, 17), GOLD, DARK_TEXT)
    y2 = y + ch + 100
    text_block(d, (28, y2), 'Kart otomatik algılanır, fotoğraf çekmenize gerek yok',
               font(SB, 18), (203, 213, 225), sw - 56, 24)
    bw = (sw - 32 - 12) / 2
    for i, t in enumerate(('Fotoğraf çek', 'Elle gir')):
        bx = 16 + i * (bw + 12)
        d.rounded_rectangle([bx, sh - 92, bx + bw, sh - 36], 16, outline=LINE, width=2,
                            fill=(255, 255, 255, 10))
        f = font(B, 20)
        d.text((bx + (bw - d.textlength(t, font=f)) / 2, sh - 76), t, font=f, fill=WHITE)


def scr_form(img, d, top):
    sw = img.width
    card(d, (16, top, sw - 16, top + 176))
    d.text((34, top + 12), 'Ad soyad', font=font(XB, 19), fill=WHITE)
    check(d, sw - 46, top + 24, 12, BLUE)
    hw = (sw - 32 - 36 - 10) / 2
    field(d, (34, top + 44, 34 + hw, top + 112), 'Ad', 'Mehmet')
    field(d, (44 + hw, top + 44, sw - 34, top + 112), 'Soyad', 'Yılmaz')
    d.text((34, top + 122), 'Doğum yılı 1990 · kimlikten geldi', font=font(M, 15), fill=APP_MUTED)
    d.text((34, top + 145), 'Türkçe harfleri düzelt (ı, ğ, ş, ü, ö, ç)', font=font(B, 15),
           fill=BLUE)
    y = top + 188
    # Kart boyu çiplerin kaç satıra sarıldığına göre: önce ölçülür, sonra çizilir.
    pos, sub = ['Kaleci', 'Defans', 'Orta Saha', 'Forvet'], ['Defansif', 'Merkez', 'Ofansif']
    probe = Dr(Image.new('RGBA', img.size))
    yy = chips(probe, 34, y + 44, pos, None, sw - 68, 15)
    bottom = chips(probe, 34, yy + 42, sub, None, sw - 68, 15) + 16
    card(d, (16, y, sw - 16, bottom))
    d.text((34, y + 12), 'Mevki', font=font(XB, 19), fill=WHITE)
    chips(d, 34, y + 44, pos, 'Orta Saha', sw - 68, 15)
    d.text((34, yy + 12), 'Alt Mevki · Orta Saha', font=font(XB, 17), fill=WHITE)
    chips(d, 34, yy + 42, sub, 'Merkez', sw - 68, 15)
    y = bottom + 12
    card(d, (16, y, sw - 16, y + 112))
    d.text((34, y + 12), 'Fiziksel', font=font(XB, 19), fill=WHITE)
    field(d, (34, y + 40, 34 + hw, y + 100), 'Boy (cm)', '178')
    field(d, (44 + hw, y + 40, sw - 34, y + 100), 'Kilo (kg)', '76')
    y += 124
    card(d, (16, y, sw - 16, y + 92))
    d.text((34, y + 12), 'Kullandığı Ayak', font=font(XB, 19), fill=WHITE)
    chips(d, 34, y + 44, ['Sağ', 'Sol', 'Her İkisi'], 'Sağ', sw - 68, 15)
    y += 104
    button(d, (16, y, img.width - 16, y + 58), 'İLERİ')


def scr_phone(img, d, top):
    sw = img.width
    text_block(d, (22, top - 6), 'Numaranı doğrula ve şifreni belirle. Giriş yaparken bu '
               'numara ve şifreyi kullanacaksın.', font(M, 17), (255, 255, 255, 190), sw - 44,
               23)
    y = top + 60
    field(d, (16, y, sw - 16, y + 72), 'Cep Telefonu', '0 (532) 123 45 67')
    check(d, sw - 46, y + 36, 13, ACCENT)
    y += 84
    d.text((22, y), "Numaranıza WhatsApp'tan 6 haneli bir", font=font(M, 15), fill=APP_MUTED)
    d.text((22, y + 20), 'doğrulama kodu göndereceğiz.', font=font(M, 15), fill=APP_MUTED)
    y += 52
    bw = (sw - 32 - 5 * 8) / 6
    for i, ch in enumerate('481207'):
        bx = 16 + i * (bw + 8)
        d.rounded_rectangle([bx, y, bx + bw, y + 66], 14, fill=(255, 255, 255, 12), outline=ACCENT,
                            width=2)
        f = font(XB, 30)
        d.text((bx + (bw - d.textlength(ch, font=f)) / 2, y + 14), ch, font=f, fill=WHITE)
    highlight(img, (16, y, sw - 16, y + 66), 14)
    d = Dr(img)
    y += 90
    field(d, (16, y, sw - 16, y + 72), 'Şifre Belirle', '••••••••')
    y += 82
    field(d, (16, y, sw - 16, y + 72), 'Şifre (Tekrar)', '••••••••')
    y += 88
    for t in ('6-10 karakter', 'En az 1 rakam veya özel karakter',
              'Kolay tahmin edilemez (123456, 111111 değil)', 'İki şifre aynı'):
        check(d, 32, y + 10, 10, ACCENT, width=3)
        d.text((52, y), t, font=font(SB, 16), fill=(203, 213, 225))
        y += 28
    y += 12
    button(d, (16, y, sw - 16, y + 58), 'PROFİLİMİ OLUŞTUR')


# ---------------------------------------------------------------- kare iskeleti

def frame(n, step, title, title2, sub, brand_x=64):
    c = lm_outro.BG.copy().crop((0, 0, W, H))
    d = Dr(c)
    y = 64
    if step:
        pill(d, 64, y, f'ADIM {step} / {STEPS}', font(XB, 26), GOLD, DARK_TEXT, pad=(20, 9))
        y += 74
    d.text((60, y), title, font=font(HEAD, 92), fill=WHITE)
    y += 98
    if title2:
        d.text((60, y), title2, font=font(HEAD, 92), fill=GOLD)
        y += 98
    if sub:
        y = text_block(d, (64, y + 6), sub, font(M, 32), MUTED, W - 128, 42)
    # alt bant
    crest = Image.open(CREST).convert('RGBA').resize((54, 54), Image.LANCZOS)
    c.alpha_composite(crest, (brand_x, H - 86))
    d.text((brand_x + 66, H - 76), 'LİG MASASI', font=font(HEAD, 34), fill=WHITE)
    s = f'{n} / {TOTAL}'
    f = font(XB, 26)
    d.text((W - 64 - d.textlength(s, font=f), H - 72), s, font=f, fill=MUTED)
    return c, y


def tips(c, x, y, items, width, num=True):
    """Numaralı ipuçları: (kalın satır, açıklama)."""
    d = Dr(c)
    for i, (head, body) in enumerate(items):
        if num:
            d.ellipse([x, y + 2, x + 46, y + 48], fill=GOLD)
            s = str(i + 1)
            f = font(XB, 28)
            d.text((x + 23 - d.textlength(s, font=f) / 2, y + 6), s, font=f, fill=DARK_TEXT)
        tx = x + (64 if num else 0)
        yy = text_block(d, (tx, y), head, font(B, 33), WHITE, width - (tx - x), 40)
        if body:
            yy = text_block(d, (tx, yy + 4), body, font(M, 27), MUTED, width - (tx - x), 35)
        y = yy + 34
    return y


def place_phone(c, ph, x, y):
    c.alpha_composite(ph, (x - 50, y - 50))


# ---------------------------------------------------------------- kareler

def k1_cover():
    c = lm_outro.BG.copy().crop((0, 0, W, H))
    d = Dr(c)
    crest = Image.open(CREST).convert('RGBA').resize((170, 170), Image.LANCZOS)
    c.alpha_composite(crest, ((W - 170) // 2, 60))
    center(d, 250, 'FUTBOLCU KAYDI', font(HEAD, 120), WHITE)
    center(d, 380, 'Hesabını 6 adımda aç', font(HEAD, 64), GOLD)
    center(d, 470, 'Kayıt yaklaşık 3 dakika sürer. Başlamadan önce yanında olsun:',
           font(M, 30), MUTED)
    bw, gap, y = 296, 24, 540
    x0 = (W - (bw * 3 + gap * 2)) // 2
    items = (('Çipli kimlik kartı', 'Yeni tip T.C. kimlik'),
             ("NFC'li telefon", 'Yoksa bir yakınınınki'),
             ('Cep numaran', "Kod WhatsApp'tan gelir"))
    for i, (t, s) in enumerate(items):
        x = x0 + i * (bw + gap)
        d.rounded_rectangle([x, y, x + bw, y + 230], 26, fill=(255, 255, 255, 16),
                            outline=(255, 255, 255, 40), width=2)
        ix, iy = x + bw // 2, y + 66
        if i == 0:
            d.rounded_rectangle([ix - 52, iy - 33, ix + 52, iy + 33], 9, fill=(214, 226, 240))
            d.rounded_rectangle([ix - 40, iy - 14, ix - 14, iy + 8], 4, fill=GOLD)
            d.rounded_rectangle([ix + 4, iy - 18, ix + 40, iy + 22], 4, fill=(150, 163, 184))
        elif i == 1:
            d.rounded_rectangle([ix - 26, iy - 44, ix + 26, iy + 44], 10, outline=WHITE, width=5)
            for k, rr in enumerate((18, 32, 46)):
                d.arc([ix + 10 - rr, iy - rr, ix + 10 + rr, iy + rr], -40, 40, fill=GOLD,
                      width=5)
        else:
            d.rounded_rectangle([ix - 48, iy - 32, ix + 48, iy + 24], 16, fill=ACCENT)
            d.polygon([(ix - 26, iy + 20), (ix - 36, iy + 42), (ix - 6, iy + 22)], fill=ACCENT)
            f = font(XB, 30)
            d.text((ix - d.textlength('••••', font=f) / 2, iy - 22), '••••', font=f, fill=WHITE)
        center(d, y + 130, t, font(B, 30), WHITE, w=bw, x0=x)
        center(d, y + 172, s, font(M, 24), MUTED, w=bw, x0=x)
    y = 820
    steps = ('Uygulamayı indir, Kayıt Ol', 'Futbolcu Profili’ni seç',
             'Kimliğin arka yüzünü tara', 'Kimlik çipini okut',
             'Mevki ve bilgilerini gir', 'Numaranı doğrula, şifre belirle')
    for i, s in enumerate(steps):
        col, row = i % 2, i // 2
        x = 90 + col * 470
        yy = y + row * 92
        d.ellipse([x, yy, x + 54, yy + 54], fill=GOLD)
        n = str(i + 1)
        f = font(XB, 30)
        d.text((x + 27 - d.textlength(n, font=f) / 2, yy + 7), n, font=f, fill=DARK_TEXT)
        text_block(d, (x + 70, yy + 10), s, font(SB, 28), WHITE, 380, 32)
    center(d, 1110, 'Uygulama: ligmasasi.com/indir', font(B, 32), WHITE)
    center(d, H - 140, 'Adımlar sonraki görsellerde  »', font(B, 30), GOLD)
    s = f'1 / {TOTAL}'
    f = font(XB, 26)
    d.text((W - 64 - d.textlength(s, font=f), H - 72), s, font=f, fill=MUTED)
    return c


def k2_download():
    c, y = frame(2, 1, 'UYGULAMAYI İNDİR,', '“KAYIT OL”A DOKUN', None, brand_x=580)
    ph = phone(420, 900, None, scr_login)
    place_phone(c, ph, 70, 360)
    d = Dr(c)
    x, w = 580, 440
    yy = text_block(d, (x, 380), 'Lig Masası’nı App Store veya Google Play’den indir:',
                    font(B, 33), WHITE, w, 40)
    d.rounded_rectangle([x, yy + 18, x + w, yy + 96], 18, fill=(255, 255, 255, 18),
                        outline=GOLD, width=3)
    center(d, yy + 34, 'ligmasasi.com/indir', font(XB, 36), GOLD, w=w, x0=x)
    yy += 130
    for badge in (APPLE, GOOGLE):
        b = badge.resize((round(badge.width * 84 / badge.height), 84), Image.LANCZOS)
        c.alpha_composite(b, (x, int(yy)))
        yy += 104
    d = Dr(c)
    yy += 20
    yy = tips(c, x, yy, [('Uygulamayı aç, giriş ekranında “Kayıt Ol”a dokun.', None),
                         ('Web sitesinden kayıt olunmaz.',
                          'Kimlik çipi yalnızca uygulamadan okunur.')], w)
    return c


def k3_choice_real():
    c, y = frame(3, 2, '“FUTBOLCU', 'PROFİLİ”Nİ SEÇ', None, brand_x=580)
    ph = phone(420, 900, 'Kayıt Ol', scr_choice)
    place_phone(c, ph, 70, 360)
    tips(c, 580, 400, [('Yeşil “Futbolcu Profili” kartına dokun.', None),
                       ('Turuncu kart turnuva kuracaklar içindir.',
                        'Futbolcular bu kartı seçmez.'),
                       ('Bilgilerin güvende.',
                        'Kimlikten yalnız ad, soyad ve doğum tarihi alınır. TC numaran '
                        'geri dönülemez şekilde şifrelenir, kimse göremez.')], 440)
    return c


def k4_mrz():
    c, y = frame(4, 3, 'KİMLİĞİN ARKA', 'YÜZÜNÜ TARA', None, brand_x=580)
    ph = phone(420, 900, 'Kimliğini Doğrula', scr_mrz)
    place_phone(c, ph, 70, 360)
    tips(c, 580, 400, [('“Kimliğimi Okut”, ardından “Arka Yüzü Okut”a dokun.', None),
                       ('Kartın arka yüzünü kameraya göster.',
                        'Alttaki 3 satır yazı otomatik okunur. Fotoğraf saklanmaz.'),
                       ('Okumazsa “Elle gir” ile bilgileri yaz.',
                        'Seri no, doğum tarihi ve son geçerlilik tarihi kartta yazar.'),
                       ('Kamera izni sorulursa “İzin ver” de.', None)], 440)
    return c


def phone_back(w, h, kind):
    """Telefonun arkası + kimlik kartı + NFC dalgaları."""
    im = Image.new('RGBA', (w + 120, h + 120), (0, 0, 0, 0))
    d = Dr(im)
    ox, oy = 60, 60
    sh = Image.new('RGBA', im.size, (0, 0, 0, 0))
    Dr(sh).rounded_rectangle([ox, oy + 16, ox + w, oy + h + 16], 54, fill=(0, 0, 0, 150))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(22)))
    d.rounded_rectangle([ox, oy, ox + w, oy + h], 54, fill=(44, 52, 68), outline=(96, 108, 130),
                        width=4)
    if kind == 'ios':
        d.rounded_rectangle([ox + 22, oy + 22, ox + 128, oy + 128], 28, fill=(28, 34, 46))
        for cx, cy in ((ox + 52, oy + 52), (ox + 52, oy + 98), (ox + 98, oy + 75)):
            d.ellipse([cx - 19, cy - 19, cx + 19, cy + 19], fill=(10, 12, 18),
                      outline=(90, 100, 120), width=3)
        target = oy + 150
    else:
        d.rounded_rectangle([ox + 26, oy + 26, ox + 76, oy + 170], 24, fill=(28, 34, 46))
        for cy in (oy + 54, oy + 100, oy + 144):
            d.ellipse([ox + 33, cy - 18, ox + 69, cy + 18], fill=(10, 12, 18),
                      outline=(90, 100, 120), width=3)
        target = oy + h // 2 - 70
    cw, ch = w - 30, int((w - 30) / 1.585)
    cx0 = ox + 15
    cy0 = target
    # NFC dalgaları (kart merkezinden)
    mx, my = ox + w // 2, cy0 + ch // 2
    glow = Image.new('RGBA', im.size, (0, 0, 0, 0))
    gd = Dr(glow)
    for rr in (cw * .6, cw * .75):
        gd.arc([mx - rr, my - rr, mx + rr, my + rr], -28, 28, fill=GOLD + (240,), width=6)
        gd.arc([mx - rr, my - rr, mx + rr, my + rr], 152, 208, fill=GOLD + (240,), width=6)
    im.alpha_composite(glow)
    # kartın ön yüzü
    cardi = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
    grad_box(cardi, (0, 0, cw, ch), (236, 214, 222), (196, 220, 240), 14)
    cd = Dr(cardi)
    cd.rectangle([0, 0, cw, ch * .18], fill=(200, 40, 50))
    f = font(B, max(10, int(ch * .08)))
    cd.text((cw * .05, ch * .04), 'TÜRKİYE CUMHURİYETİ KİMLİK KARTI', font=f, fill=WHITE)
    cd.rounded_rectangle([cw * .06, ch * .32, cw * .32, ch * .86], 6, fill=(160, 172, 190))
    cd.rounded_rectangle([cw * .40, ch * .36, cw * .58, ch * .6], 5, fill=GOLD,
                         outline=(150, 105, 20), width=2)
    for i in range(3):
        cd.rounded_rectangle([cw * .40, ch * (.68 + i * .09), cw * (.92 - i * .1),
                              ch * (.72 + i * .09)], 3, fill=(120, 132, 150))
    im.alpha_composite(cardi.rotate(-4, resample=Image.BICUBIC, expand=True), (cx0 - 4, cy0 - 4))
    return im


def k5_chip():
    c, y = frame(5, 4, 'KİMLİK ÇİPİNİ', 'OKUT', None)
    d = Dr(c)
    for i, (kind, label, sub) in enumerate((('ios', 'iPhone', 'Üst kısım, kameranın altı'),
                                            ('and', 'Android', 'Arka orta'))):
        ph = phone_back(260, 520, kind)
        x = 110 + i * 300
        c.alpha_composite(ph, (x - 60, 330))
        d = Dr(c)
        center(d, 930, label, font(XB, 34), WHITE, w=260, x0=x)
        center(d, 972, sub, font(M, 24), MUTED, w=260, x0=x)
    tips(c, 720, 380, [('“Çipi Oku”ya bas.', None),
                       ('Kartı telefonun arkasına düz yasla.', None),
                       ('Birkaç saniye oynatma.', 'Okumazsa kartı biraz kaydırıp bekle.')],
         310)
    yy = 1030
    d = Dr(c)
    d.rounded_rectangle([64, yy, W - 64, yy + 196], 24, fill=(255, 255, 255, 14),
                        outline=(255, 255, 255, 36), width=2)
    text_block(d, (96, yy + 26), 'Android’de “NFC kapalı” çıkarsa:', font(B, 30), GOLD, 880, 36)
    text_block(d, (96, yy + 68), 'Ayarlar › Bağlantılar › NFC’yi aç. Kalın kılıf okumayı '
               'engelleyebilir, gerekirse çıkar. Telefonunda NFC yoksa bir yakınının '
               'telefonuyla da kayıt olabilirsin.', font(M, 27), MUTED, 880, 36)
    return c


def k6_form():
    c, y = frame(6, 5, 'MEVKİ VE', 'BİLGİLERİNİ GİR', None, brand_x=580)
    ph = phone(420, 900, 'Futbolcu Profili', scr_form, progress=2)
    place_phone(c, ph, 70, 360)
    tips(c, 580, 400, [('Adın ve soyadın kimlikten gelir.',
                        'Kimlik çipinde Türkçe harf yoktur. “Türkçe harfleri düzelt” ile '
                        'ı, ğ, ş, ü, ö, ç harflerini düzeltebilirsin.'),
                       ('Mevkini ve alt mevkini seç.', None),
                       ('İstersen boy, kilo ve kullandığın ayağı gir.', '(Boş bırakılabilir)'),
                       ('“İleri”ye dokun.', None)], 440)
    return c


def k7_phone():
    c, y = frame(7, 6, 'NUMARANI DOĞRULA,', 'ŞİFRE BELİRLE', None, brand_x=580)
    ph = phone(420, 900, 'Telefon Doğrulama', scr_phone, progress=3)
    place_phone(c, ph, 70, 360)
    tips(c, 580, 400, [('Cep numaranı yaz, “Kod Gönder”e dokun.', None),
                       ("6 haneli kod WhatsApp'tan gelir.",
                        'Kodun gelmesi birkaç dakika sürebilir. Gelmezse “Kodu tekrar gönder”.'),
                       ('Şifreni belirle.',
                        '6-10 karakter, en az 1 rakam. 123456 gibi kolay şifreler olmaz.'),
                       ('“Profilimi Oluştur”a dokun.', None)], 440)
    return c


def k8_done():
    c = lm_outro.BG.copy().crop((0, 0, W, H))
    d = Dr(c)
    glow = Image.new('RGBA', c.size, (0, 0, 0, 0))
    Dr(glow).ellipse([W / 2 - 100, 40, W / 2 + 100, 240], fill=BLUE + (90,))
    c.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))
    d = Dr(c)
    check(d, W // 2, 135, 72, BLUE, width=16)
    center(d, 222, 'PROFİLİN HAZIR!', font(HEAD, 96), WHITE)
    center(d, 330, 'Profilin mavi tikli, kimlikle onaylı görünür.', font(M, 30), MUTED)
    center(d, 368, 'Bundan sonra numaran ve şifrenle giriş yaparsın.', font(M, 30), MUTED)
    y = 430
    qa = (('Kimliğimi okutmak güvenli mi?',
           'Evet. Kimlikten yalnız adın, soyadın ve doğum tarihin alınır. TC Kimlik No geri '
           'dönülemez şekilde şifrelenir; kimse, biz dahil, göremez. Kimlikteki fotoğrafın '
           'okunmaz, kartın taranan görüntüsü saklanmaz.'),
          ('Zaten bir takımın kadrosundayım.',
           'Tekrar eklenmen gerekmez. Kaydın kadrodaki profilinle otomatik eşleşir; maçların '
           've istatistiklerin aynen kalır.'),
          ('Zaten kayıtlıyım uyarısı çıktı?',
           'Bu kimlikle açılmış bir hesabın var. Giriş ekranında “Şifremi Unuttum” ile '
           'şifreni yenile.'),
          ('Telefonumda NFC yok.',
           'Bir yakınının telefonuyla kayıt ol; kimlik bilgilerin o telefonda kalmaz. Sonra '
           'kendi telefonundan numaran ve şifrenle gir.'),
          ('Kod gelmedi.',
           'Birkaç dakika bekle, sonra “Kodu tekrar gönder”e dokun. Numarayı doğru '
           'yazdığından emin ol.'))
    fa = font(M, 25)
    for i, (q, a) in enumerate(qa):
        hh = 54 + len(wrap(d, a, fa, 884)) * 32 + 22
        d.rounded_rectangle([64, y, W - 64, y + hh], 22,
                            fill=(56, 189, 248, 26) if i == 0 else (255, 255, 255, 14),
                            outline=BLUE + (120,) if i == 0 else (255, 255, 255, 36), width=2)
        d.text((96, y + 16), q, font=font(B, 29), fill=BLUE if i == 0 else GOLD)
        text_block(d, (96, y + 56), a, fa, (220, 228, 238), 884, 32)
        y += hh + 14
    crest = Image.open(CREST).convert('RGBA').resize((54, 54), Image.LANCZOS)
    c.alpha_composite(crest, (64, H - 86))
    d.text((130, H - 76), 'LİG MASASI', font=font(HEAD, 34), fill=WHITE)
    s = f'{TOTAL} / {TOTAL}'
    f = font(XB, 26)
    d.text((W - 64 - d.textlength(s, font=f), H - 72), s, font=f, fill=MUTED)
    return c


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else HERE
    os.makedirs(out, exist_ok=True)
    slides = (k1_cover, k2_download, k3_choice_real, k4_mrz, k5_chip, k6_form, k7_phone, k8_done)
    for i, fn in enumerate(slides, 1):
        img = fn().convert('RGB')
        path = os.path.join(out, f'futbolcu_kaydi_{i}.jpg')
        img.save(path, quality=92)
        print(path)


if __name__ == '__main__':
    main()
