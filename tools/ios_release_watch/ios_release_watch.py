#!/usr/bin/env python3
"""iOS sürüm onayı izleyici (tek seferlik, launchd her 15 dakikada çalıştırır).

App Store Connect'te VERSION yayına girince (READY_FOR_SALE) yalnızca iPhone
kullanıcılarına güncelleme bildirimi gönderir, admin'e Telegram'dan haber
verir ve kendini kapatır. Ret gelirse bildirim göndermez, yalnız Telegram.

Kurulum: ~/Library/LaunchAgents/com.ligmasasi.ios-release-watch.plist
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, 'tool'))
import asc  # noqa: E402

VERSION = '1.0.6'
LABEL = 'com.ligmasasi.ios-release-watch'
CONF = os.path.expanduser('~/.config/football_tournament')
DONE = os.path.join(CONF, f'ios_release_watch_{VERSION}.done')
ADMIN = 'dbda21cf-2015-43fb-87b1-cc3bf5a1e322'
REJECTED = {'REJECTED', 'METADATA_REJECTED', 'DEVELOPER_REJECTED', 'INVALID_BINARY'}

TITLE = 'LigMasası güncellendi ⚽'
BODY = ('Haftanın Enleri, yüksek kaliteli gol videoları ve Kariyerim ekranı '
        "geldi. App Store'dan güncelleyin.")


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
    sql(f"select public.telegram_notify(array[{lit(ADMIN)}]::uuid[], {lit(text)})")


def stop():
    open(DONE, 'w').write('ok')
    subprocess.run(['launchctl', 'bootout', f'gui/{os.getuid()}/{LABEL}'])


def main():
    if os.path.exists(DONE):
        stop()
        return
    aid = asc.app_id()
    v = next((x for x in asc.versions(aid)
              if x['attributes']['versionString'] == VERSION), None)
    state = v['attributes']['appStoreState'] if v else 'YOK'
    print('durum:', VERSION, state, flush=True)
    if state == 'READY_FOR_SALE':
        # Yalnız iPhone: Android kaydı da olan kişiye gitmesin.
        ids = ("(select array_agg(distinct user_id) from public.push_subscriptions "
               "where platform = 'ios' and user_id not in (select user_id from "
               "public.push_subscriptions where platform <> 'ios'))")
        n = sql(f"select coalesce(cardinality({ids}), 0)")
        sql(f"select public.push_send({ids}, {lit(TITLE)}, {lit(BODY)}, '/', 'update-ios')")
        telegram(f'✅ iOS {VERSION} onaylandı ve App Store\'da yayında. '
                 f'Güncelleme bildirimi {n} iPhone kullanıcısına gönderildi.')
        stop()
    elif state in REJECTED:
        telegram(f'⚠️ iOS {VERSION} Apple tarafından reddedildi ({state}). '
                 'Bildirim gönderilmedi; App Store Connect\'e bakın.')
        stop()


if __name__ == '__main__':
    main()
