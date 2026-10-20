"""Dört kısa Reels: Tribün / Saha / Kulübe / Afiş.

Telefon ekranda sabit kalır; dokunulan düğmede dokunma halkası belirir ve
ekran bir sonrakine geçer. Hepsi ana sayfayla başlar (Afiş hariç).

Kullanım: python reels4.py <images_dir> <out_dir> [--stills] [--only name]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

import reel
from reel import (W, H, FPS, WHITE, MUTED, GOLD, F_HEAD, F_SUB, F_SMALL,
                  ease_out, ease_in_out, text_center, font, fix_stream,
                  load_screen, crest, rounded_mask)
from reels3 import outro, cut_rows, fade, make_intro

OUT = sys.argv[2]
STILLS = '--stills' in sys.argv
ONLY = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else None

# ---------------------------------------------------------------- ekran boyu
# Tüm ekranlar aynı boya getirilir (945 geniş, 1820 yüksek, kaynak piksel):
# telefon akış boyunca yerinde kalsın.
SRC_W, SRC_H = 945, 1820
SCREEN_W = 690
SCALE = SCREEN_W / SRC_W
SCREEN_H = round(SRC_H * SCALE)
BEZEL, RADIUS, PAD = 16, 58, 70
PHONE_Y = 340


def norm(img, top, bottom=None):
    """Kırpar ve SRC_H'ye tamamlar (alt kısım sayfanın zemin rengiyle)."""
    if img.width != SRC_W:
        img = img.resize((SRC_W, round(img.height * SRC_W / img.width)), Image.LANCZOS)
    bottom = min(bottom or img.height, top + SRC_H)
    part = img.crop((0, top, SRC_W, bottom))
    if part.height < SRC_H:
        fill = part.getpixel((8, part.height - 4))
        out = Image.new('RGB', (SRC_W, SRC_H), fill)
        out.paste(part, (0, 0))
        part = out
    return part


def screen_img(img):
    return img.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)


# Telefon çerçevesi (ekransız) bir kez çizilir.
def make_frame():
    pw, ph = SCREEN_W + 2 * BEZEL, SCREEN_H + 2 * BEZEL
    out = Image.new('RGBA', (pw + 2 * PAD, ph + 2 * PAD), (0, 0, 0, 0))
    sh = Image.new('RGBA', out.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [PAD + 10, PAD + 30, PAD + pw - 10, PAD + ph + 10], RADIUS + BEZEL, fill=(0, 0, 0, 170))
    out = Image.alpha_composite(out, sh.filter(ImageFilter.GaussianBlur(36)))
    ImageDraw.Draw(out).rounded_rectangle([PAD, PAD, PAD + pw, PAD + ph], RADIUS + BEZEL,
                                          fill=(6, 9, 16, 255), outline=(58, 72, 98, 255), width=3)
    return out


FRAME = make_frame()
FX = (W - FRAME.width) // 2
SX, SY = FX + PAD + BEZEL, PHONE_Y + PAD + BEZEL  # ekranın tuvaldeki sol üstü
MASK = rounded_mask((SCREEN_W, SCREEN_H), RADIUS)


def to_canvas(pt, top):
    """Kaynak ekran görüntüsündeki nokta -> tuval koordinatı."""
    x, y = pt
    return SX + x * SCALE, SY + (y - top) * SCALE


# ---------------------------------------------------------------- Instagram hikâyesi
def story_screen(poster):
    """Afişi Instagram hikâyesi görünümünde (marka logosu olmadan) çizer."""
    s = Image.new('RGB', (SCREEN_W, SCREEN_H), (0, 0, 0))
    pw = SCREEN_W
    ph = round(poster.height * pw / poster.width)
    p = poster.resize((pw, ph), Image.LANCZOS)
    s.paste(p, (0, (SCREEN_H - ph) // 2))
    d = ImageDraw.Draw(s, 'RGBA')
    # Üstte hikâye ilerleme çubukları.
    for i in range(3):
        x0 = 14 + i * (SCREEN_W - 28) / 3
        d.rounded_rectangle([x0 + 3, 16, x0 + (SCREEN_W - 28) / 3 - 3, 21], 3,
                            fill=(255, 255, 255, 255 if i == 0 else 110))
    # Profil: arma + hesap adı.
    av = crest.resize((54, 54), Image.LANCZOS)
    s.paste(av, (18, 34), av)
    d.text((84, 38), 'ligmasasi', font=font('Barlow-Bold.ttf', 26), fill=WHITE)
    d.text((84 + d.textlength('ligmasasi', font=font('Barlow-Bold.ttf', 26)) + 12, 40), '1 dk',
           font=font('Barlow-Medium.ttf', 24), fill=(220, 220, 220))
    # Altta mesaj kutusu.
    d.rounded_rectangle([18, SCREEN_H - 78, SCREEN_W - 120, SCREEN_H - 26], 26,
                        outline=(255, 255, 255, 200), width=2)
    d.text((40, SCREEN_H - 68), 'Mesaj gönder', font=font('Barlow-Medium.ttf', 26), fill=(235, 235, 235))
    # Kalp.
    hx, hy = SCREEN_W - 92, SCREEN_H - 52
    d.ellipse([hx - 14, hy - 12, hx, hy + 2], outline=WHITE, width=3)
    d.ellipse([hx - 2, hy - 12, hx + 12, hy + 2], outline=WHITE, width=3)
    d.line([hx - 13, hy, hx - 1, hy + 14], fill=WHITE, width=3)
    d.line([hx + 11, hy, hx - 1, hy + 14], fill=WHITE, width=3)
    # Gönder oku.
    ax, ay = SCREEN_W - 48, SCREEN_H - 52
    d.polygon([(ax - 16, ay - 14), (ax + 16, ay), (ax - 16, ay + 14), (ax - 8, ay)], outline=WHITE)
    return s


# ---------------------------------------------------------------- akış sahnesi
class Step:
    def __init__(self, screen, title, sub, dur, top=0, tap=None, arrow=None):
        self.arrow = arrow  # sürükle-bırak oku: ((x0, y0), (x1, y1)) kaynak koordinatı
        self.screen = screen  # SCREEN_W x SCREEN_H
        self.title, self.sub, self.dur = title, sub, dur
        self.top, self.tap = top, tap  # tap: kaynak koordinatı (x, y)


TAP_LEN = 0.9   # düğme vurgusu süresi (adımın sonunda)
XFADE = 0.4     # ekranlar arası geçiş


def draw_headline(canvas, title, sub, a_title, a_sub, dy=0):
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if a_title > 0:
        f, size = F_HEAD, 104
        while d.textlength(title, font=f) > W - 90:
            size -= 4
            f = font('BarlowCondensed-ExtraBoldItalic.ttf', size)
        text_center(d, 140 + dy + (104 - size) * 0.6, title, f, WHITE, int(255 * a_title))
    if a_sub > 0:
        text_center(d, 262 + dy, sub, F_SUB, MUTED, int(255 * a_sub))
    return Image.alpha_composite(canvas, layer)


def highlight(scr, rect, top, k):
    """Basılan düğmeyi öne çıkarır: çevre kararır, düğme hafifçe büyür ve
    altın çerçeveyle parlar. k: 0..1 ilerleme."""
    x0, y0, x1, y1 = rect
    r = [x0 * SCALE, (y0 - top) * SCALE, x1 * SCALE, (y1 - top) * SCALE]
    a = ease_out(k / 0.35)
    base = scr.convert('RGBA')
    dark = Image.new('RGBA', base.size, (5, 8, 16, int(135 * a)))
    out = Image.alpha_composite(base, dark)
    # Düğme: kararmamış hâli, hafif büyütülmüş ("basılıyor" hissi).
    pop = 1 + 0.07 * a - 0.03 * ease_in_out((k - 0.55) / 0.45)
    box = tuple(round(v) for v in r)
    btn = base.crop(box)
    bw, bh = btn.size
    nw, nh = max(1, round(bw * pop)), max(1, round(bh * pop))
    btn = btn.resize((nw, nh), Image.LANCZOS)
    cx, cy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
    px, py = round(cx - nw / 2), round(cy - nh / 2)
    rad = min(22, nh // 2)
    # Parıltı.
    glow = Image.new('RGBA', base.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([px - 10, py - 10, px + nw + 10, py + nh + 10], rad + 10,
                                           fill=GOLD + (int(150 * a),))
    out = Image.alpha_composite(out, glow.filter(ImageFilter.GaussianBlur(14)))
    out.paste(btn, (px, py), rounded_mask((nw, nh), rad))
    ImageDraw.Draw(out).rounded_rectangle([px - 3, py - 3, px + nw + 3, py + nh + 3], rad + 3,
                                          outline=GOLD + (int(255 * a),), width=5)
    return out.convert('RGB')


def draw_arrow(scr, arrow, top, k):
    """Sürüklenen oyuncunun eski yerinden yeni yerine kesik çizgili ok."""
    (x0, y0), (x1, y1) = arrow
    p0 = (x0 * SCALE, (y0 - top) * SCALE)
    p1 = (x1 * SCALE, (y1 - top) * SCALE)
    q = ease_out(k / 0.6)
    out = scr.convert('RGBA')
    layer = Image.new('RGBA', out.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # Eski yer: kesik halka.
    r = 30
    for a in range(0, 360, 30):
        import math
        a1, a2 = math.radians(a), math.radians(a + 18)
        d.arc([p0[0] - r, p0[1] - r, p0[0] + r, p0[1] + r], a, a + 18, fill=WHITE + (int(230 * q),), width=4)
    # Ok gövdesi (ilerledikçe uzar).
    ex = p0[0] + (p1[0] - p0[0]) * q
    ey = p0[1] + (p1[1] - p0[1]) * q
    n = 8
    for i in range(n):
        t0, t1 = i / n, (i + 0.6) / n
        if t0 > 1:
            break
        d.line([p0[0] + (ex - p0[0]) * t0, p0[1] + (ey - p0[1]) * t0,
                p0[0] + (ex - p0[0]) * min(t1, 1), p0[1] + (ey - p0[1]) * min(t1, 1)],
               fill=GOLD + (255,), width=6)
    import math
    ang = math.atan2(ey - p0[1], ex - p0[0])
    L = 22
    d.polygon([(ex, ey),
               (ex - L * math.cos(ang - 0.5), ey - L * math.sin(ang - 0.5)),
               (ex - L * math.cos(ang + 0.5), ey - L * math.sin(ang + 0.5))], fill=GOLD + (255,))
    return Image.alpha_composite(out, layer).convert('RGB')


def draw_tap(canvas, pt, k):
    """k: 0..1 dokunma ilerlemesi (önce parmak izi belirir, sonra halka yayılır)."""
    x, y = pt
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if k < 0.45:
        q = ease_out(k / 0.45)
        r = 52 - 12 * q
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, int(150 * q)),
                  outline=(255, 255, 255, int(230 * q)), width=4)
    else:
        q = (k - 0.45) / 0.55
        r = 40
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, int(150 * (1 - q))))
        rr = 40 + 70 * ease_out(q)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], outline=(255, 255, 255, int(220 * (1 - q))), width=6)
    return Image.alpha_composite(canvas, layer)


def flow(steps):
    starts, t0 = [], 0.0
    for s in steps:
        starts.append(t0)
        t0 += s.dur
    total = t0

    def render(t, dur):
        i = max(j for j, s in enumerate(starts) if t >= s)
        st, lt = steps[i], t - starts[i]
        c = reel.BG.copy()
        # Başlık: ilk adımda kayarak gelir; sonra değişen kısım çapraz geçer.
        if i == 0:
            k = ease_out(lt / 0.45)
            k2 = ease_out((lt - 0.12) / 0.45)
            c = draw_headline(c, st.title, st.sub, k, k2, dy=(1 - k) * 40)
            line_k = k
        else:
            prev = steps[i - 1]
            k = ease_in_out(lt / XFADE)
            same_title = prev.title == st.title
            if same_title:
                c = draw_headline(c, st.title, prev.sub, 1, 1 - k)
                c = draw_headline(c, st.title, st.sub, 0, k)
            else:
                c = draw_headline(c, prev.title, prev.sub, 1 - k, 1 - k)
                c = draw_headline(c, st.title, st.sub, k, k)
            line_k = 1
        d = ImageDraw.Draw(c)
        lw = 120 * line_k
        d.rounded_rectangle([W / 2 - lw / 2, 118, W / 2 + lw / 2, 126], 4,
                            fill=GOLD + (int(255 * line_k),))
        # Telefon: yalnız ilk adımda aşağıdan gelir.
        enter = ease_out(t / 0.55)
        oy = round((1 - enter) * 240)
        frame = FRAME if enter >= 1 else fade(FRAME, enter)
        c.alpha_composite(frame, (FX, PHONE_Y + oy))
        scr = st.screen
        if st.tap and lt > st.dur - TAP_LEN:
            k = (lt - (st.dur - TAP_LEN)) / TAP_LEN
            scr = highlight(scr, st.tap, st.top, k)
            if st.arrow:
                scr = draw_arrow(scr, st.arrow, st.top, k)
        if i > 0 and lt < XFADE:
            prev = steps[i - 1]
            pscr = highlight(prev.screen, prev.tap, prev.top, 1.0) if prev.tap else prev.screen
            scr = Image.blend(pscr, scr, ease_in_out(lt / XFADE))
        scr = scr.convert('RGBA')
        if enter < 1:
            scr = fade(scr, enter)
        holder = Image.new('RGBA', (SCREEN_W, SCREEN_H), (0, 0, 0, 0))
        holder.paste(scr, (0, 0), MASK)
        c.alpha_composite(holder, (SX, SY + oy))
        return c
    return total, render


# ---------------------------------------------------------------- ekranlar
def build():
    raw = {n: load_screen(n) for n in
           (32, 46, 47, 49, 60, 61, 65, 43, 41, 40, 64, 33, 5, 38, 36, 37, 42, 63, 62, 66,
            50, 51, 52, 53, 54)}
    raw[46] = cut_rows(raw[46], 1055, 1252)
    raw[33] = fix_stream(raw[33])
    WEB_TOP, WEB_BOT = 206, 1888
    web = (47, 50, 51, 52, 53, 54, 60, 61, 62, 63, 64, 65, 66)
    tops = {n: WEB_TOP for n in web + (46,)}
    tops.update({49: 0, 33: 120})
    bots = {n: WEB_BOT for n in web}
    bots[46] = WEB_BOT - 197
    S, T = {}, {}
    for n, img in raw.items():
        top = tops.get(n, 97)
        S[n] = screen_img(norm(img, top, bots.get(n)))
        T[n] = top
    # Afişler (kaynak kutuları ölçüldü).
    poster = {50: raw[50].crop((180, 632, 765, 1670)), 53: raw[53].crop((177, 540, 728, 1580))}
    story = {n: story_screen(p) for n, p in poster.items()}

    def st(n, title, sub, dur, tap=None, arrow=None):
        return Step(S[n], title, sub, dur, T[n], tap, arrow)

    HOME_MATCH = (32, 1519, 913, 1663)  # 'Bu hafta' Moda – Maltepe satırı (kesik sonrası)
    TT = 'TEK EKRANDAN, TEK DOKUNUŞLA'
    reels = {
        'tribun': [
            st(32, 'TRİBÜN', 'Girişe gerek yok, tüm turnuvaları takip et', 2.2,
               tap=(41, 735, 904, 883)),
            st(46, 'TURNUVAN CEBİNDE', 'Bu haftanın maçları ve son dakika haberleri', 2.4),
            st(47, 'KRALLIK YARIŞI', 'Gol ve asist krallığı her maçtan sonra güncel', 2.4,
               tap=(745, 352, 910, 412)),
            # 49 (1080 geniş) 945'e küçültülür: sekme kutusu bu ölçekte.
            st(49, 'PUAN DURUMU', 'Averaj ve form otomatik hesaplanır', 2.3,
               tap=(258, 262, 462, 345)),
            st(60, 'FİKSTÜR', 'Hafta hafta tüm maçlar ve sonuçlar', 2.2,
               tap=(470, 468, 685, 565)),
            st(61, 'İSTATİSTİK', 'Gol, asist, maçın adamı, kartlar', 2.2,
               tap=(675, 468, 940, 565)),
            st(65, 'HABERLER', 'Turnuvanın tüm haberleri tek yerde', 2.3),
        ],
        'saha': [
            st(32, 'SAHA', 'Futbolcu girişi', 2.1, tap=(41, 425, 459, 710)),
            st(46, 'MAÇINI TAKİP ET', 'Bu haftanın maçları ana sayfada', 2.1, tap=HOME_MATCH),
            st(43, 'DAKİKA DAKİKA MAÇ', 'Goller, kartlar, oyuncu değişiklikleri', 2.3,
               tap=(712, 712, 945, 790)),
            st(41, 'DİZİLİŞ', 'Sahadaki 11, iki takım için', 2.1, tap=(473, 722, 896, 794)),
            st(40, 'DİZİLİŞ', 'Yuvarlak ya da forma görünümü', 2.1),
            st(64, 'SÜRÜKLE, BIRAK', 'Oyuncuyu tut, sahada istediğin yere taşı', 2.4,
               tap=(415, 985, 590, 1160), arrow=((612, 1000), (500, 1040))),
            st(33, 'MAÇ YAYINI', 'Canlı yayın bağlantısı maç sayfasında', 2.1),
            st(5, 'OYUNCU PROFİLİ', 'Her futbolcunun istatistiği tek kartta', 2.3),
        ],
        'kulube': [
            st(32, 'KULÜBE', 'Takım ve turnuva sorumlusu girişi', 2.1, tap=(485, 425, 904, 710)),
            st(46, TT, 'Maçı seç', 1.9, tap=HOME_MATCH),
            st(33, TT, 'Yönetim menüsü maç sayfasında', 1.9, tap=(759, 1825, 895, 1958)),
            st(66, TT, 'Hızlı skor girişi', 2.0, tap=(497, 978, 886, 1075)),
            st(38, TT, 'Skoru gir, kaydet', 2.0, tap=(111, 1251, 834, 1374)),
            st(66, TT, 'Maç detayı: dakika dakika olaylar', 2.0, tap=(507, 1126, 886, 1224)),
            st(36, TT, 'Gol, penaltı, kart, değişiklik, maçın adamı', 2.0,
               tap=(111, 717, 834, 809)),
            st(37, TT, 'Golü atan, dakika, asist', 1.9, tap=(106, 1577, 839, 1704)),
            st(42, TT, 'Maç kadrosu ve esame', 2.0, tap=(50, 880, 200, 945)),
            st(63, TT, 'Esame: ilk 11 tek dokunuşla seçilir', 2.1, tap=(505, 515, 905, 600)),
            st(62, TT, 'Yedekleri seç, kaydet', 2.2, tap=(43, 1745, 901, 1868)),
        ],
        'afis': [
            st(50, 'AFİŞİN HAZIR', 'Haftanın fikstürü, otomatik', 2.2, tap=(96, 1710, 850, 1838)),
            Step(story[50], 'INSTAGRAM HİKAYENDE', 'Tek dokunuşla paylaş', 2.2),
            st(51, 'SONUÇ AFİŞİ', 'Hafta biter bitmez skorlar hazır', 2.0, tap=(96, 1710, 850, 1838)),
            st(54, 'MAÇ AFİŞİ', 'Her maç için ayrı tasarım', 2.0, tap=(92, 1620, 842, 1750)),
            st(52, 'İLK 11', 'Diziliş, forma numaralarıyla', 2.0, tap=(92, 1620, 842, 1750)),
            st(53, 'MAÇ KADROSU', 'İlk 11 ve yedekler', 2.0, tap=(92, 1620, 842, 1750)),
            Step(story[53], 'INSTAGRAM HİKAYENDE', 'Tek dokunuşla paylaş', 2.2),
        ],
    }
    return reels


THEMES = {
    'tribun': ((23, 37, 84), (30, 58, 138), 'TRİBÜN', 'Turnuvan cebinde'),
    'saha': ((11, 61, 36), (22, 163, 74), 'SAHA', 'Her maç kayıt altında'),
    'kulube': ((84, 45, 8), (217, 119, 6), 'KULÜBE', 'Maçı tek ekrandan yönet'),
    'afis': ((74, 20, 60), (190, 24, 93), 'AFİŞ', 'Tek dokunuşla Instagram\'da'),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    reels = build()
    for name, steps in reels.items():
        if ONLY and name != ONLY:
            continue
        reel.BG = reel.make_background(THEMES[name][0])
        total, render = flow(steps)
        scenes = [(1.5, make_intro(THEMES[name])), (total, render), (2.6, outro)]
        if STILLS:
            t = 0
            for j, s in enumerate(steps):
                # Her adımın dokunma anı (varsa) ya da ortası.
                at = t + (s.dur - TAP_LEN * 0.6 if s.tap else s.dur * 0.6)
                render(at, total).convert('RGB').save(f'{OUT}/{name}_{j}.jpg', quality=85)
                t += s.dur
            continue
        d = f'{OUT}/{name}'
        os.makedirs(d, exist_ok=True)
        n = 0
        for dur, fn in scenes:
            for f in range(round(dur * FPS)):
                fn(f / FPS, dur).convert('RGB').save(f'{d}/f_{n:05d}.jpg', quality=92)
                n += 1
        dur, fn = scenes[0]
        fn(dur, dur).convert('RGB').save(f'{OUT}/{name}_kapak.jpg', quality=92)
        print(name, n, 'kare', round(n / FPS, 1), 'sn')


if __name__ == '__main__':
    main()
