#!/usr/bin/env python3
"""Mağaza onayı izleyici: iOS + Android (launchd her 15 dakikada çalıştırır).

Kullanım: store_release_watch.py <sürüm> <derleme>   (ör. 1.0.8 257)

- iOS: App Store Connect'te sürüm READY_FOR_SALE olunca (ve seçili derleme
  <derleme> ise) admin'e Telegram. Ret gelirse de Telegram.
- Android: Play production kanalında <derleme> var VE Play Store sayfasındaki
  "Updated on" tarihi izleme başladığındaki tarihten farklıysa (= yeni sürüm
  mağazada yayında) admin'e Telegram. Play API inceleme durumunu vermediği
  için mağaza sayfası okunur.
Onay gelince o platform için hemen app_settings.app_update.<platform>.latest =
<derleme> yazılır (uygulama içi "Yeni sürüm mevcut" kartı). Eski sürümdeki
kullanıcılara "güncelleme" telefon bildirimi yalnız 10:00-22:00 (İstanbul)
arasında gider; gece onaylanırsa 10:00'dan sonraki ilk çalışmada gönderilir.
Bildirim ana anahtarı kapalı olana gitmez (push_send p_force).
Her şey bitince launchd işini kapatır.

Kurulum: ~/Library/LaunchAgents/com.ligmasasi.store-release-watch.plist
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, 'tool'))
import asc  # noqa: E402
import play_upload as play  # noqa: E402

LABEL = 'com.ligmasasi.store-release-watch'
CONF = os.path.expanduser('~/.config/football_tournament')
ADMIN = 'dbda21cf-2015-43fb-87b1-cc3bf5a1e322'
REJECTED = {'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'}
PLAY_PAGE = ('https://play.google.com/store/apps/details?id=com.ligmasasi.app'
             '&hl=en&gl=TR')


def sql(q):
    db = open(os.path.join(CONF, 'db.env')).read().strip()
    out = subprocess.run(['psql', db, '-v', 'ON_ERROR_STOP=1', '-Atc', q],
                         capture_output=True, text=True)
    if out.returncode:
        raise RuntimeError(out.stderr.strip())
    return out.stdout.strip()


def lit(s):
    return "'" + s.replace("'", "''") + "'"


def telegram(text):
    sql(f"select public.telegram_notify(array[{lit(ADMIN)}]::uuid[], {lit(text)}, null, null)")


PUSH_TITLE = 'Lig Masası güncellendi ⚽'
PUSH_BODY = 'Yeni sürüm hazır. Güncellemek için dokunun.'


def set_latest(platform, build):
    sql("update public.app_settings set value = jsonb_set(value, "
        f"'{{{platform},latest}}', to_jsonb({int(build)})) where key = 'app_update'")


def quiet_now():
    # 22:00-10:00 İstanbul: güncelleme bildirimi gönderilmez.
    h = int(sql("select extract(hour from now() at time zone 'Europe/Istanbul')::int"))
    return h >= 22 or h < 10


def send_update_push(platform, build):
    # Bu platformda son 60 günde görülen ve bu platformdaki hiçbir cihazı
    # henüz <derleme>'ye geçmemiş kullanıcılar.
    ids = ("(select array_agg(user_id) from (select user_id from public.app_clients "
           f"where platform = {lit(platform)} and user_id is not null "
           "and last_seen > now() - interval '60 days' "
           "and app_version like '%+%' group by user_id "
           "having max(nullif(split_part(app_version, '+', 2), '')::int) "
           f"< {int(build)}) x)")
    n = sql(f"select coalesce(cardinality({ids}), 0)")
    sql(f"select public.push_send({ids}, {lit(PUSH_TITLE)}, {lit(PUSH_BODY)}, "
        f"'/', 'update-{platform}', true)")
    return n


def ios_state(version, build):
    aid = asc.app_id()
    v = next((x for x in asc.versions(aid)
              if x['attributes']['versionString'] == version), None)
    if not v:
        return 'YOK', None
    b = asc.call('GET', f"/appStoreVersions/{v['id']}/build").get('data')
    return v['attributes']['appStoreState'], (b or {}).get('attributes', {}).get('version')


def play_production_codes():
    tok = play.token()
    e = play.call(tok, 'POST', f'{play.API}/edits', b'{}')['id']
    try:
        t = play.call(tok, 'GET', f'{play.API}/edits/{e}/tracks/production')
    finally:
        play.call(tok, 'DELETE', f'{play.API}/edits/{e}')
    codes = set()
    for r in t.get('releases', []):
        if r.get('status') in ('completed', 'inProgress'):
            codes.update(r.get('versionCodes', []))
    return codes


def play_updated_on():
    req = urllib.request.Request(PLAY_PAGE, headers={'User-Agent': 'Mozilla/5.0'})
    html = urllib.request.urlopen(req, timeout=30).read().decode('utf-8', 'replace')
    m = re.search(r'Updated on</div><div[^>]*>([^<]+)', html)
    return m.group(1).strip() if m else None


def main():
    if len(sys.argv) != 3:
        sys.exit('kullanım: store_release_watch.py <sürüm> <derleme>')
    version, build = sys.argv[1], sys.argv[2]
    path = os.path.join(CONF, f'store_release_watch_{version}_{build}.json')
    st = json.load(open(path)) if os.path.exists(path) else {}

    if not st.get('ios_done'):
        state, sel = ios_state(version, build)
        print('ios:', version, state, 'derleme', sel, flush=True)
        if state == 'READY_FOR_SALE' and sel == build:
            set_latest('ios', build)
            telegram(f"✅ iOS {version} ({build}) onaylandı ve App Store'da yayında. "
                     "Uygulama içi güncelleme kartı açıldı.")
            st['ios_done'] = True
            st['ios_push'] = True
        elif state in REJECTED:
            telegram(f"⚠️ iOS {version} ({build}) Apple tarafından reddedildi ({state}). "
                     "App Store Connect'e bakın.")
            st['ios_done'] = True

    if not st.get('android_done'):
        updated = play_updated_on()
        st.setdefault('play_baseline', updated)
        in_prod = build in play_production_codes()
        print('android: production', build, in_prod, 'güncelleme', updated,
              'başlangıç', st['play_baseline'], flush=True)
        if in_prod and updated and updated != st['play_baseline']:
            set_latest('android', build)
            telegram(f"✅ Android {version} ({build}) onaylandı ve Google Play'de yayında "
                     f"(güncelleme tarihi {updated}). Uygulama içi güncelleme kartı açıldı.")
            st['android_done'] = True
            st['android_push'] = True

    # Bekleyen güncelleme bildirimleri: yalnız 10:00-22:00.
    for platform, name in (('ios', 'iOS'), ('android', 'Android')):
        if st.get(f'{platform}_push') and not quiet_now():
            n = send_update_push(platform, build)
            telegram(f"📲 {name} güncelleme bildirimi {n} kullanıcıya gönderildi.")
            st[f'{platform}_push'] = False
        json.dump(st, open(path, 'w'))

    json.dump(st, open(path, 'w'))
    if (st.get('ios_done') and st.get('android_done')
            and not st.get('ios_push') and not st.get('android_push')):
        subprocess.run(['launchctl', 'bootout', f'gui/{os.getuid()}/{LABEL}'])


if __name__ == '__main__':
    main()
