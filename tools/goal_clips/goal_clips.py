#!/usr/bin/env python3
"""Gol kesitlerini MP4'e çevirir (Mac'te, launchd ile birkaç dakikada bir).

Onaylı gol kesitleri (match_highlights, YouTube aralığı) için:
  1. YouTube yayınından yalnız gol aralığı indirilir (tam yayın inmez).
  2. İki MP4 üretilir: yatay (16:9, köşede Lig Masası) ve Instagram hikâyesi
     (9:16: turnuva logosu, maç sonucu, GOL!, golcü, golle gelen skor).
  3. clips deposuna yüklenir; match_highlights.clip_url / story_url yazılır.
  4. Bir kopyası Drive'daki maç klasörüne (adında #LMxxxxxx kodu olan,
     "Gol Kesitleri" alt klasörü) bırakılır; klasör yoksa ARCHIVE_DIR altına
     (Lig / N. Hafta / Maç).
Pasif turnuvaların maçları taranmaz.

Kullanım: goal_clips.py [--match <id>] [--limit N]
Veritabanı: ~/.config/football_tournament/db.env (yazdırılmaz).
Yükleme: admin.env'deki admin hesabıyla (clips deposuna yalnız admin yazar).
"""
import argparse
import datetime
import glob
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CFG = os.path.expanduser('~/.config/football_tournament')
FONTS = os.path.join(ROOT, 'assets', 'fonts')
APP_LOGO = os.path.join(ROOT, 'assets', 'images', 'app_logo.png')
SUPABASE_URL = 'https://qxdjebzszikeslobrozf.supabase.co'
ARCHIVE_DIR = os.environ.get(
    'ARCHIVE_DIR', os.path.expanduser('~/Desktop/LigMasasi-Kesitler'))
DRIVE_ROOTS = glob.glob(os.path.expanduser(
    '~/Library/CloudStorage/GoogleDrive-*/*/LigMasasi'))
BREW = '/opt/homebrew/bin'
LEAD, LENGTH = 0, 20  # özetteki başlangıç (gol - 12 sn) → 20 sn: golden 12 sn önce, 8 sn sonra
MAX_TRIES = 3


def log(*a):
    print(datetime.datetime.now().strftime('%H:%M:%S'), *a, flush=True)


def psql(sql):
    with open(os.path.join(CFG, 'db.env')) as f:
        url = f.read().strip()
    out = subprocess.run(['psql', url, '-At', '-v', 'ON_ERROR_STOP=1', '-c', sql],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def q(v):
    return "'" + str(v).replace("'", "''") + "'"


def anon_key():
    src = open(os.path.join(ROOT, 'lib', 'core', 'config', 'app_config.dart')).read()
    i = src.index("'SUPABASE_ANON_KEY'")
    j = src.index('eyJ', i)
    k = j
    while k < len(src) and (src[k].isalnum() or src[k] in '._-'):
        k += 1
    return src[j:k]


_token = None


def admin_token():
    global _token
    if _token:
        return _token
    env = {}
    for line in open(os.path.join(CFG, 'admin.env')):
        if '=' in line:
            k, v = line.strip().split('=', 1)
            env[k] = v.strip().strip('"').strip("'")
    req = urllib.request.Request(
        f'{SUPABASE_URL}/auth/v1/token?grant_type=password',
        data=json.dumps({'email': env['ADMIN_EMAIL'], 'password': env['ADMIN_PASSWORD']}).encode(),
        headers={'apikey': anon_key(), 'Content-Type': 'application/json'})
    _token = json.load(urllib.request.urlopen(req))['access_token']
    return _token


def upload(path, key):
    with open(path, 'rb') as f:
        data = f.read()
    req = urllib.request.Request(
        f'{SUPABASE_URL}/storage/v1/object/clips/{key}', data=data, method='POST',
        headers={'apikey': anon_key(), 'Authorization': f'Bearer {admin_token()}',
                 'Content-Type': 'video/mp4', 'x-upsert': 'true',
                 'Cache-Control': 'max-age=31536000'})
    urllib.request.urlopen(req).read()
    return f'{SUPABASE_URL}/storage/v1/object/public/clips/{key}'


# Kesit bilgileri: maç, takımlar, logolar, maç sonucu, golle gelen skor.
QUERY = """
with h as (
  select h.*, m.home_team_id, m.away_team_id, m.home_score, m.away_score,
         m.match_date, m.week, m.league_id
    from public.match_highlights h
    join public.matches m on m.id = h.match_id
    join public.leagues lg on lg.id = m.league_id
   where h.kind = 'goal' and h.status = 'approved'
     and lg.status = 'active' and coalesce(lg.is_active, true)
     and h.video_id !~ '^http'
     and h.story_url is null and h.clip_tries < {tries}
     and m.status = 'finished'
     {extra}
   order by h.created_at desc
   limit {limit}
), ev as (
  select e.match_id, e.id, e.team_id, e.is_own_goal,
         row_number() over (partition by e.match_id
                            order by e.minute, coalesce(e.added_minute, 0), e.created_at) as n,
         e.minute, e.added_minute, e.player_id, e.assist_player_id
    from public.match_events e
   where e.event_type = 'goal' and e.match_id in (select match_id from h)
)
select json_agg(json_build_object(
  'id', h.id, 'match_id', h.match_id, 'video_id', h.video_id,
  'start', h.start_sec, 'minute', h.minute, 'added', h.added_minute,
  'week', h.week, 'date', h.match_date,
  'league', l.name, 'league_logo', l.logo_url,
  'home', ht.name, 'away', at.name,
  'home_logo', ht.logo_url, 'away_logo', at.logo_url,
  'home_color', ht.first_color, 'away_color', at.first_color,
  'fh', h.home_score, 'fa', h.away_score,
  'team', st.name, 'side', case when h.team_id = h.away_team_id then 'away' else 'home' end,
  'scorer', coalesce(nullif(trim(p.name || ' ' || p.surname), ''),
                     (select trim(pp.name || ' ' || pp.surname)
                        from ev join public.players pp on pp.id = ev.player_id
                       where ev.id = h.match_event_id)),
  'assist', (select nullif(trim(pa.name || ' ' || pa.surname), '')
               from ev join public.players pa on pa.id = ev.assist_player_id
              where ev.id = h.match_event_id and not coalesce(ev.is_own_goal, false)),
  'rh', (select count(*) from ev where ev.match_id = h.match_id and r.upto >= ev.n
           and ((ev.team_id = h.home_team_id) <> coalesce(ev.is_own_goal, false))),
  'ra', (select count(*) from ev where ev.match_id = h.match_id and r.upto >= ev.n
           and ((ev.team_id = h.away_team_id) <> coalesce(ev.is_own_goal, false)))
))
from h
join public.leagues l on l.id = h.league_id
join public.teams ht on ht.id = h.home_team_id
join public.teams at on at.id = h.away_team_id
left join public.teams st on st.id = h.team_id
left join public.players p on p.id = h.player_id
cross join lateral (
  -- Bu gole kadar olan goller: bağlı olaya kadar; bağ yoksa dakikaya kadar.
  select coalesce(
    (select ev.n from ev where ev.id = h.match_event_id),
    (select max(ev.n) from ev where ev.match_id = h.match_id
        and ev.minute <= coalesce(h.minute, 0)),
    0) as upto
) r
"""


def short(n):
    return (n or '').replace(' Masterler', '').replace(' Masterlar', '').strip()


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def fetch(url, path):
    if not url:
        return None
    try:
        urllib.request.urlretrieve(url, path)
        Image.open(path).convert('RGBA')
        return path
    except Exception:
        return None


def story_overlay(c, out, logos, zoom=1.0):
    """9:16 katman: üstte turnuva + maç sonucu, altta GOL!, golcü, golle skor."""
    W, H = 1080, 1920
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    GOLD = (226, 184, 69, 255)
    WHITE = (255, 255, 255, 255)
    MUTED = (203, 213, 225, 255)

    def ctext(y, t, fo, fill, cx=W / 2):
        w = d.textlength(t, font=fo)
        d.text((cx - w / 2, y), t, font=fo, fill=fill)

    def logo(path, cx, cy, size, alpha=1.0, shadow=False):
        if not path:
            return
        lg = Image.open(path).convert('RGBA')
        lg.thumbnail((size, size), Image.LANCZOS)
        if alpha < 1:
            lg.putalpha(lg.getchannel('A').point(lambda v: int(v * alpha)))
        if shadow:
            sh = Image.new('RGBA', lg.size, (0, 0, 0, 0))
            sh.putalpha(lg.getchannel('A').point(lambda v: int(v * 0.65)))
            sh = sh.filter(ImageFilter.GaussianBlur(size * 0.06))
            im.alpha_composite(sh, (int(cx - lg.width / 2), int(cy - lg.height / 2 + size * 0.05)))
        im.alpha_composite(lg, (int(cx - lg.width / 2), int(cy - lg.height / 2)))

    def rgba(h, a=255, default='#1F2937'):
        h = (h or default).strip().lstrip('#')
        try:
            return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)
        except ValueError:
            return rgba(default, a)

    # Üstte okunurluk için yumuşak koyu geçiş.
    shade = Image.linear_gradient('L').resize((W, 548)).transpose(Image.FLIP_TOP_BOTTOM)
    dark = Image.new('RGBA', (W, 548), (0, 0, 0, 255))
    dark.putalpha(shade.point(lambda v: int(v * 0.45)))
    im.alpha_composite(dark, (0, 0))

    # Turnuva logosu + adı
    logo(logos['league'], W / 2, 90, 110, shadow=True)
    ctext(152, (c['league'] or '').upper(), font('BarlowCondensed-ExtraBold.ttf', 34), GOLD)

    # Maç sonucu bandı: iki takımın renginde, çapraz bölünmüş; skor beyaz kartta.
    y0, y1 = 210, 520
    bh = y1 - y0
    band = Image.new('RGBA', (W, bh), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    bd.polygon([(0, 0), (W / 2 + 60, 0), (W / 2 - 60, bh), (0, bh)],
               fill=rgba(c.get('home_color'), 235))
    bd.polygon([(W / 2 + 60, 0), (W, 0), (W, bh), (W / 2 - 60, bh)],
               fill=rgba(c.get('away_color'), 235, '#334155'))
    shade = Image.new('RGBA', (W, bh), (0, 0, 0, 255))
    shade.putalpha(Image.linear_gradient('L').resize((W, bh)).point(lambda v: int(v * 0.55)))
    band.alpha_composite(shade)
    im.alpha_composite(band, (0, y0))
    d.line([(W / 2 + 60, y0), (W / 2 - 60, y1)], fill=(255, 255, 255, 120), width=4)
    logo(logos['home'], 200, y0 + 125, 170, shadow=True)
    logo(logos['away'], W - 200, y0 + 125, 170, shadow=True)
    for name, cx in ((short(c['home']).upper(), 200), (short(c['away']).upper(), W - 200)):
        size = 36
        while size > 22 and d.textlength(name, font=font('BarlowCondensed-ExtraBold.ttf', size)) > 330:
            size -= 2
        fo = font('BarlowCondensed-ExtraBold.ttf', size)
        w = d.textlength(name, font=fo)
        d.text((cx - w / 2 + 2, y0 + 227), name, font=fo, fill=(0, 0, 0, 150))
        d.text((cx - w / 2, y0 + 225), name, font=fo, fill=WHITE)
    INK = (12, 18, 32, 255)
    bx0, bx1, by0, by1 = W / 2 - 125, W / 2 + 125, y0 + 70, y0 + 230
    d.rounded_rectangle((bx0, by0, bx1, by1), 26, fill=(255, 255, 255, 250))
    d.rounded_rectangle((bx0, by0 - 34, bx1, by0 + 6), 14, fill=GOLD)
    lab, lf = 'MAÇ SONUCU', font('BarlowCondensed-ExtraBold.ttf', 28)
    lw = sum(d.textlength(ch, font=lf) for ch in lab) + 2 * (len(lab) - 1)
    x = W / 2 - lw / 2
    for ch in lab:
        d.text((x, by0 - 30), ch, font=lf, fill=INK)
        x += d.textlength(ch, font=lf) + 2
    ctext(by0 + 14, f"{c['fh']}-{c['fa']}", font('BarlowCondensed-ExtraBold.ttf', 120), INK)

    # GOL! + dakika + golcü; asist varsa altında küçük satır (herkes aynı
    # hikâyeyi paylaşır, asist yapanın adı da görünür).
    assist = (c.get('assist') or '').upper() if c.get('scorer') else ''
    minute = f"{c['minute']}+{c['added']}'" if c.get('added') else f"{c['minute']}'"
    ctext(1290, 'GOL!', font('BarlowCondensed-ExtraBoldItalic.ttf', 160), GOLD)
    who = f"{minute}  {c['scorer']}" if c.get('scorer') else f"{minute}  {short(c['team'])}"
    fo = font('BarlowCondensed-ExtraBold.ttf', 72 if assist else 76)
    if d.textlength(who, font=fo) > W - 80:
        fo = font('BarlowCondensed-ExtraBold.ttf', 60)
    ctext(1458 if assist else 1470, who, fo, WHITE)
    if assist:
        GREEN = (52, 211, 153, 255)
        tag, tf = 'ASİST', font('BarlowCondensed-ExtraBold.ttf', 34)
        nf = font('BarlowCondensed-ExtraBold.ttf', 44)
        tw, nw = d.textlength(tag, font=tf), d.textlength(assist, font=nf)
        x = (W - (tw + 28 + 16 + nw)) / 2
        y = 1534
        d.rounded_rectangle((x, y + 4, x + tw + 28, y + 50), 10, outline=GREEN, width=3)
        d.text((x + 14, y + 8), tag, font=tf, fill=GREEN)
        d.text((x + tw + 28 + 16, y), assist, font=nf, fill=MUTED)

    # Golle gelen skor: iki takımın logosu arasında; golü atan tarafın
    # sayısı altın rengi.
    sf = font('BarlowCondensed-ExtraBold.ttf', 92)
    hs, as_ = str(c['rh']), str(c['ra'])
    dash = ' - '
    w_h, w_d, w_a = (d.textlength(t, font=sf) for t in (hs, dash, as_))
    total = w_h + w_d + w_a
    x = (W - total) / 2
    y = 1590 if assist else 1565
    pad = 26
    d.rounded_rectangle((x - 110 - pad, y - 4, x + total + 110 + pad, y + 112),
                        radius=58, fill=(11, 18, 32, 190), outline=(226, 184, 69, 140), width=2)
    logo(logos['home'], x - 60, y + 54, 76)
    logo(logos['away'], x + total + 60, y + 54, 76)
    d.text((x, y), hs, font=sf, fill=GOLD if c['side'] == 'home' else WHITE)
    d.text((x + w_h, y), dash, font=sf, fill=MUTED)
    d.text((x + w_h + w_d, y), as_, font=sf, fill=GOLD if c['side'] == 'away' else WHITE)

    # Lig Masası imzası
    fb = font('BarlowCondensed-ExtraBold.ttf', 62)
    tw = d.textlength('LİG MASASI', font=fb)
    x0 = (W - (90 + 16 + tw)) / 2
    logo(APP_LOGO, x0 + 45, 1757, 90)
    d.text((x0 + 106, 1720), 'LİG MASASI', font=fb, fill=WHITE)

    # Video köşe filigranı: maç görüntüsünün sağ alt köşesi (make ile aynı yer).
    vh = 1080 * zoom * 9 / 16
    bottom = (H + vh) / 2 if zoom == 1 else 545 + (735 + vh) / 2
    logo(APP_LOGO, W - 22 - 39, bottom - 18 - 39, 78, alpha=0.9)
    im.save(out)


def wide_overlay(out):
    """16:9 katman: sağ altta Lig Masası logosu ve yazısı."""
    y = Image.new('RGBA', (1920, 1080), (0, 0, 0, 0))
    d = ImageDraw.Draw(y)
    fy = font('BarlowCondensed-ExtraBold.ttf', 44)
    tw = d.textlength('LİG MASASI', font=fy)
    bw = int(76 + 14 + tw + 28)
    x0, y0 = 1920 - bw - 30, 1080 - 130
    y.alpha_composite(Image.new('RGBA', (bw, 100), (11, 18, 32, 150)), (x0, y0))
    lg = Image.open(APP_LOGO).convert('RGBA')
    lg.thumbnail((76, 76), Image.LANCZOS)
    y.alpha_composite(lg, (x0 + 14, y0 + 12))
    d.text((x0 + 14 + 76 + 14, y0 + 22), 'LİG MASASI', font=fy, fill=(255, 255, 255, 255))
    y.save(out)


def run(cmd):
    env = dict(os.environ, PATH=f"{BREW}:{os.environ.get('PATH', '')}")
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip()[-400:])


def hms(s):
    return f'{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}'


# Kalite ayarları. Eski (FMT_STD): YouTube'un 1080p MP4'ü (çoğu zaman düşük
# bit hızlı AV1) + CRF 21. Varsayılan: 4K/1440p kaynak 1080p'ye küçültülür,
# CRF 17; hikâyede maç görüntüsü %18 büyütülür.
FMT_STD = 'bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080]'
FMT_HQ = 'bv*[height<=2160]+ba/b'


def make(c, tmp, fmt=FMT_HQ, crf='17', preset='slow', zoom=1.18):
    """zoom > 1: hikâyede maç görüntüsü yanlardan kırpılıp büyütülür."""
    s = max(0, int(c['start']) - LEAD)
    src = os.path.join(tmp, 'src.mp4')
    run([f'{BREW}/yt-dlp', '-q', '--no-warnings', '--no-playlist',
         '-f', fmt,
         '--download-sections', f'*{hms(s)}-{hms(s + LENGTH)}',
         '--force-keyframes-at-cuts', '--merge-output-format', 'mp4',
         '-o', src, f"https://www.youtube.com/watch?v={c['video_id']}"])
    logos = {k: fetch(c.get(f'{k}_logo') if k != 'league' else c.get('league_logo'),
                      os.path.join(tmp, f'{k}.png'))
             for k in ('league', 'home', 'away')}
    ov, ovw = os.path.join(tmp, 'story.png'), os.path.join(tmp, 'wide.png')
    story_overlay(c, ov, logos, zoom)
    wide_overlay(ovw)
    story, wide = os.path.join(tmp, 'story.mp4'), os.path.join(tmp, 'wide.mp4')
    run([f'{BREW}/ffmpeg', '-v', 'error', '-y', '-i', src, '-i', ov, '-filter_complex',
         '[0:v]split[a][b];[a]scale=-2:1920,crop=1080:1920,gblur=sigma=40,eq=brightness=-0.18[bg];'
         f'[b]scale={round(1080 * zoom / 2) * 2}:-2:flags=lanczos,crop=1080:ih[fg];'
         # Büyütülen görüntü maç sonucu bandı (545) ile GOL! (1280) arasına.
         f"[bg][fg]overlay=0:{'(H-h)/2' if zoom == 1 else '545+(735-h)/2'}[v];"
         '[v][1:v]overlay=0:0,format=yuv420p[out]',
         '-map', '[out]', '-map', '0:a?', '-c:v', 'libx264', '-preset', preset, '-crf', crf,
         '-r', '30', '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', story])
    run([f'{BREW}/ffmpeg', '-v', 'error', '-y', '-i', src, '-i', ovw, '-filter_complex',
         '[0:v]scale=1920:1080:flags=lanczos[v];[v][1:v]overlay=0:0,format=yuv420p[out]',
         '-map', '[out]', '-map', '0:a?', '-c:v', 'libx264', '-preset', preset, '-crf', crf,
         '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', wide])
    return wide, story


_drive_folders = None


def drive_match_folder(match_id):
    """Drive'da adı '#LM' + maç kimliğinin ilk 6 hanesiyle biten klasör."""
    global _drive_folders
    if _drive_folders is None:
        _drive_folders = {}
        for root in DRIVE_ROOTS:
            for dirpath, dirnames, _ in os.walk(root):
                for d in dirnames:
                    i = d.rfind('#LM')
                    if i >= 0:
                        _drive_folders[d[i + 3:i + 9].upper()] = os.path.join(dirpath, d)
                # Maç klasörlerinin içine inme (fotoğraflar, kesitler).
                dirnames[:] = [d for d in dirnames if '#LM' not in d]
    return _drive_folders.get(match_id.replace('-', '')[:6].upper())


def archive(c, wide, story):
    folder = drive_match_folder(c['match_id'])
    if folder:
        folder = os.path.join(folder, 'Gol Kesitleri')
    else:
        date = datetime.date.fromisoformat(c['date']).strftime('%d.%m.%Y') if c.get('date') else ''
        week = f"{c['week']}. Hafta" if c.get('week') else 'Diğer'
        match = f"{short(c['home'])} {c['fh']}-{c['fa']} {short(c['away'])} ({date})"
        folder = os.path.join(ARCHIVE_DIR, c['league'] or 'Lig', week, match)
    os.makedirs(folder, exist_ok=True)
    base = f"{c['minute']}' {c.get('scorer') or short(c['team'])}".replace('/', '-')
    for src, kind in ((story, 'hikaye'), (wide, 'yatay')):
        dst = os.path.join(folder, f'{base} ({kind}).mp4')
        with open(src, 'rb') as a, open(dst, 'wb') as b:
            b.write(a.read())


def measure_drive():
    """Drive LigMasasi klasörünün boyutu (turnuva klasörü bazında); günde bir
    kez usage_drive'a yazılır (İstatistikler › Drive)."""
    if not DRIVE_ROOTS or psql("select count(*) from public.usage_drive "
                               "where day = (now() at time zone 'Europe/Istanbul')::date") != '0':
        return
    total, by = 0, {}
    for root in DRIVE_ROOTS:
        for top in os.listdir(root):
            path = os.path.join(root, top)
            size = 0
            if os.path.isdir(path):
                for dirpath, _, files in os.walk(path):
                    for f in files:
                        try:
                            size += os.path.getsize(os.path.join(dirpath, f))
                        except OSError:
                            pass
            else:
                size = os.path.getsize(path)
            by[top] = by.get(top, 0) + size
            total += size
    psql("insert into public.usage_drive (day, bytes, by_league) values "
         f"((now() at time zone 'Europe/Istanbul')::date, {total}, {q(json.dumps(by))}::jsonb) "
         "on conflict (day) do update set bytes = excluded.bytes, by_league = excluded.by_league")
    log('Drive ölçüldü:', round(total / 1e9, 2), 'GB')


# --- Haftanın Golü hikâye videosu: 2 sn kart + gol videosu -------------------
AWARD_QUERY = """
select coalesce(json_agg(t), '[]'::json) from (
  select n.id, n.week, n.auto_data->>'league_name' as league,
         n.auto_data->>'league_logo' as league_logo, a as goal
    from public.news n, jsonb_array_elements(n.auto_data->'awards') a
   where n.auto_kind = 'week_awards' and a->>'kind' = 'goal'
     and coalesce(a->'clip'->>'story_url', '') <> ''
     and coalesce(n.auto_data->>'goal_video_url', '') = ''
     and n.created_at > now() - interval '21 days'
   limit 4
) t
"""


def tr_upper(t):
    return (t or '').replace('i', 'İ').replace('ı', 'I').upper()


def award_intro(g, out, tmp):
    """9:16 tuvalde ortalanmış 4:5 'Haftanın Golü' kartı (uygulamadaki kartın aynısı)."""
    W, H = 1080, 1920
    CW, CH = 1080, 1350
    top = (H - CH) // 2
    bg = Image.linear_gradient('L').resize((W, H))
    im = Image.merge('RGB', [bg.point(lambda v, a=a: int(a[0] + (a[1] - a[0]) * v / 255))
                             for a in ((15, 10), (23, 16), (42, 30))]).convert('RGBA')
    card = Image.new('RGBA', (CW, CH), (11, 24, 28, 255))
    d = ImageDraw.Draw(card)
    CORAL = (248, 113, 113, 255)
    GOLD = (226, 184, 69, 255)
    WHITE = (241, 245, 249, 255)
    MUTED = (203, 213, 225, 255)
    goal, pl, team = g['goal'], g['goal'].get('player') or {}, g['goal'].get('team') or {}

    # Sol: oyuncu fotoğrafı, sağ kenarı eğik kesik.
    top_x, bot_x = int(CW * 0.53), int(CW * 0.43)
    photo = fetch(goal.get('photo') or pl.get('photo'), os.path.join(tmp, 'ph.img'))
    if photo:
        ph = Image.open(photo).convert('RGBA')
        pw = top_x + 20
        scale = max(pw / ph.width, CH / ph.height)
        ph = ph.resize((int(ph.width * scale), int(ph.height * scale)), Image.LANCZOS)
        ox, oy = (ph.width - pw) // 2, int((ph.height - CH) * 0.3)
        ph = ph.crop((ox, oy, ox + pw, oy + CH))
        mask = Image.new('L', (CW, CH), 0)
        ImageDraw.Draw(mask).polygon([(0, 0), (top_x, 0), (bot_x, CH), (0, CH)], fill=255)
        layer = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
        layer.paste(ph, (0, 0))
        card.paste(layer, (0, 0), mask)
    else:
        lg = fetch(team.get('logo'), os.path.join(tmp, 'tl.img'))
        if lg:
            t = Image.open(lg).convert('RGBA')
            t.thumbnail((420, 420), Image.LANCZOS)
            card.alpha_composite(t, (80, CH // 2 - t.height // 2))

    right = CW - 56
    def rtext(y, t, fo, fill, sp=0):
        if sp:
            w = sum(d.textlength(ch, font=fo) for ch in t) + sp * (len(t) - 1)
            x = right - w
            for ch in t:
                d.text((x, y), ch, font=fo, fill=fill)
                x += d.textlength(ch, font=fo) + sp
        else:
            d.text((right - d.textlength(t, font=fo), y), t, font=fo, fill=fill)

    def fit(t, name, size, maxw):
        while size > 30 and d.textlength(t, font=font(name, size)) > maxw:
            size -= 4
        return font(name, size)

    # Üst: turnuva + hafta, sağda turnuva logosu
    ll = fetch(g.get('league_logo'), os.path.join(tmp, 'll.img'))
    lx = right
    if ll:
        t = Image.open(ll).convert('RGBA')
        t.thumbnail((96, 96), Image.LANCZOS)
        card.alpha_composite(t, (right - t.width, 56))
        lx = right - t.width - 20
    league = tr_upper(g.get('league'))
    fl = fit(league, 'BarlowCondensed-ExtraBold.ttf', 36, 440)
    d.text((lx - d.textlength(league, font=fl), 60), league, font=fl, fill=GOLD)
    wk = f"{g['week']}. HAFTA"
    fw = font('BarlowCondensed-ExtraBold.ttf', 30)
    d.text((lx - d.textlength(wk, font=fw), 106), wk, font=fw, fill=WHITE)

    # Orta: HAFTANIN GOLÜ + oyuncu adı
    rtext(470, 'HAFTANIN', font('BarlowCondensed-ExtraBold.ttf', 34), CORAL, sp=10)
    rtext(505, 'GOLÜ', font('BarlowCondensed-ExtraBoldItalic.ttf', 150), CORAL)
    parts = (pl.get('name') or '').split()
    first, last = ' '.join(parts[:-1]), (parts[-1] if parts else '')
    if first:
        rtext(690, tr_upper(first), fit(tr_upper(first), 'BarlowCondensed-ExtraBold.ttf', 70, 480), WHITE)
    fl2 = fit(tr_upper(last), 'BarlowCondensed-ExtraBoldItalic.ttf', 150, 500)
    rtext(740, tr_upper(last), fl2, CORAL)
    d.line([(right - 220, 925), (right, 925)], fill=CORAL, width=5)

    # Takım adı + arması
    tn = (team.get('name') or '').replace(' Masterlar', '').replace(' Masterler', '')
    tn = tr_upper(tn)
    tl = fetch(team.get('logo'), os.path.join(tmp, 'tl2.img'))
    tx = right
    if tl:
        t = Image.open(tl).convert('RGBA')
        t.thumbnail((82, 82), Image.LANCZOS)
        card.alpha_composite(t, (right - t.width, 950))
        tx = right - t.width - 16
    ft = fit(tn, 'BarlowCondensed-ExtraBold.ttf', 40, 380)
    d.text((tx - d.textlength(tn, font=ft), 965), tn, font=ft, fill=MUTED)

    # Alt: Lig Masası imzası
    fb = font('BarlowCondensed-ExtraBold.ttf', 44)
    tw = d.textlength('LİG MASASI', font=fb)
    d.text((right - tw, CH - 100), 'LİG MASASI', font=fb, fill=WHITE)
    al = Image.open(APP_LOGO).convert('RGBA')
    al.thumbnail((68, 68), Image.LANCZOS)
    card.alpha_composite(al, (int(right - tw - 16 - al.width), CH - 108))

    im.alpha_composite(card, (0, top))
    im.convert('RGB').save(out)


def award_videos():
    raw = psql(AWARD_QUERY)
    rows = json.loads(raw) if raw else []
    for g in rows:
        try:
            with tempfile.TemporaryDirectory() as tmp:
                intro = os.path.join(tmp, 'intro.png')
                award_intro(g, intro, tmp)
                story = os.path.join(tmp, 'story.mp4')
                urllib.request.urlretrieve(g['goal']['clip']['story_url'], story)
                out = os.path.join(tmp, 'award.mp4')
                run([f'{BREW}/ffmpeg', '-v', 'error', '-y', '-loop', '1', '-t', '2', '-i', intro,
                     '-i', story, '-f', 'lavfi', '-t', '2', '-i', 'anullsrc=r=44100:cl=stereo',
                     '-filter_complex',
                     '[0:v]fps=30,scale=1080:1920,format=yuv420p,setsar=1[v0];'
                     '[1:v]fps=30,scale=1080:1920,format=yuv420p,setsar=1[v1];'
                     '[2:a]aresample=44100,aformat=channel_layouts=stereo[a0];'
                     '[1:a]aresample=44100,aformat=channel_layouts=stereo[a1];'
                     '[v0][a0][v1][a1]concat=n=2:v=1:a=1[v][a]',
                     '-map', '[v]', '-map', '[a]', '-c:v', 'libx264', '-crf', '18',
                     '-preset', 'medium', '-c:a', 'aac', '-b:a', '128k',
                     '-movflags', '+faststart', out])
                url = upload(out, f"weekly/{g['id']}_goal.mp4")
                psql("update public.news set auto_data = jsonb_set(auto_data, '{goal_video_url}', "
                     f"to_jsonb({q(url)}::text)) where id = {q(g['id'])}")
            log('Haftanın Golü videosu hazır:', g['week'], '. hafta')
        except Exception as e:
            log('Haftanın Golü videosu HATA:', str(e)[-300:])



def main():
    try:
        measure_drive()
    except Exception as e:
        log('Drive ölçülemedi:', e)
    try:
        award_videos()
    except Exception as e:
        log('Haftanın Golü videoları:', e)
    ap = argparse.ArgumentParser()
    ap.add_argument('--match')
    ap.add_argument('--limit', type=int, default=8)
    args = ap.parse_args()
    extra = f'and h.match_id = {q(args.match)}' if args.match else \
        "and h.created_at > now() - interval '21 days'"
    raw = psql(QUERY.format(tries=MAX_TRIES, extra=extra, limit=args.limit))
    clips = json.loads(raw) if raw else []
    if not clips:
        return
    for c in clips:
        name = f"{c['minute']}' {c.get('scorer') or ''} · {short(c['home'])}-{short(c['away'])}"
        try:
            with tempfile.TemporaryDirectory() as tmp:
                wide, story = make(c, tmp)
                key = f"goals/{c['match_id']}/{c['id']}"
                wide_url = upload(wide, f'{key}.mp4')
                story_url = upload(story, f'{key}_story.mp4')
                psql(f"update public.match_highlights set clip_url = {q(wide_url)}, "
                     f"story_url = {q(story_url)}, clip_error = null where id = {q(c['id'])}")
                try:
                    archive(c, wide, story)
                except Exception as e:
                    log('arşiv kopyası yazılamadı:', e)
            log('hazır:', name)
        except Exception as e:
            msg = str(e)[-300:]
            log('HATA:', name, msg)
            psql(f"update public.match_highlights set clip_tries = clip_tries + 1, "
                 f"clip_error = {q(msg)} where id = {q(c['id'])}")


if __name__ == '__main__':
    lock = os.path.join(tempfile.gettempdir(), 'ligmasasi_goal_clips.lock')
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL)
    except FileExistsError:
        # Önceki çalışma sürüyor (ya da yarım kaldı; 30 dk sonra kilit düşer).
        if datetime.datetime.now().timestamp() - os.path.getmtime(lock) < 1800:
            sys.exit(0)
        os.remove(lock)
        fd = os.open(lock, os.O_CREAT | os.O_EXCL)
    try:
        main()
    finally:
        os.close(fd)
        os.remove(lock)
