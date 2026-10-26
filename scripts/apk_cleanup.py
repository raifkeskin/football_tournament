#!/usr/bin/env python3
"""App Distribution'da yalnız son N test APK'sını tutar, eskileri siler.

Kullanım: python3 scripts/apk_cleanup.py [N]   (varsayılan 30)
Firebase CLI oturumunun (firebase login) yenileme anahtarını kullanır.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

PROJECT = '974894815246'
APP = '1:974894815246:android:5feb335a68c9da9c1bc45f'
KEEP = int(sys.argv[1]) if len(sys.argv) > 1 else 30

# Firebase CLI'nin herkese açık OAuth istemcisi (firebase-tools ile aynı).
CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com'
CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi'


def token():
    cfg = json.load(open(os.path.expanduser('~/.config/configstore/firebase-tools.json')))
    data = urllib.parse.urlencode({
        'refresh_token': cfg['tokens']['refresh_token'],
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'grant_type': 'refresh_token',
    }).encode()
    return json.load(urllib.request.urlopen('https://oauth2.googleapis.com/token', data))['access_token']


def main():
    headers = {'Authorization': 'Bearer ' + token()}
    base = f'https://firebaseappdistribution.googleapis.com/v1/projects/{PROJECT}/apps/{APP}/releases'
    releases, page = [], ''
    while True:
        req = urllib.request.Request(f'{base}?pageSize=100&pageToken={page}', headers=headers)
        r = json.load(urllib.request.urlopen(req))
        releases += r.get('releases', [])
        page = r.get('nextPageToken')
        if not page:
            break
    releases.sort(key=lambda x: x.get('createTime', ''), reverse=True)
    old = [x['name'] for x in releases[KEEP:]]
    for i in range(0, len(old), 100):
        req = urllib.request.Request(
            f'{base}:batchDelete',
            data=json.dumps({'names': old[i:i + 100]}).encode(),
            headers={**headers, 'Content-Type': 'application/json'},
            method='POST',
        )
        urllib.request.urlopen(req)
    print(f'APK temizliği: {len(releases)} sürüm, {len(old)} silindi, {min(len(releases), KEEP)} kaldı.')


if __name__ == '__main__':
    main()
