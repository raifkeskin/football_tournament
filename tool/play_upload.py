#!/usr/bin/env python3
"""Google Play'e AAB yükler (yalnızca kullanıcı "markete taşı" dediğinde).

Kullanım:
  python3 -I tool/play_upload.py <aab> <kanal> "<sürüm notu>"
  kanal: internal | alpha (kapalı test) | beta (açık test)

Kimlik: Firebase hizmet hesabı (~/.config/football_tournament/firebase-sa.json),
Play Console'da yalnızca test kanallarına yayınlama yetkisi var. Ek Python
paketi gerekmez (JWT openssl ile imzalanır).
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

PACKAGE = 'com.ligmasasi.app'
API = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}'
UPLOAD = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}'


def token():
    sa = json.load(open(os.path.expanduser('~/.config/football_tournament/firebase-sa.json')))
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b'=')
    now = int(time.time())
    head = b64(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    claim = b64(json.dumps({
        'iss': sa['client_email'],
        'scope': 'https://www.googleapis.com/auth/androidpublisher',
        'aud': sa['token_uri'], 'iat': now, 'exp': now + 3000,
    }).encode())
    fd, kp = tempfile.mkstemp()
    try:
        os.write(fd, sa['private_key'].encode())
        os.close(fd)
        sig = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', kp],
                             input=head + b'.' + claim, capture_output=True, check=True).stdout
    finally:
        os.unlink(kp)
    assertion = (head + b'.' + claim + b'.' + b64(sig)).decode()
    body = ('grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer'
            f'&assertion={assertion}').encode()
    return json.load(urllib.request.urlopen(urllib.request.Request(sa['token_uri'], body)))['access_token']


def call(tok, method, url, data=None, ctype='application/json'):
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={'Authorization': 'Bearer ' + tok, 'Content-Type': ctype})
    try:
        r = urllib.request.urlopen(req, timeout=600)
        t = r.read()
        return json.loads(t) if t else {}
    except urllib.error.HTTPError as e:
        sys.exit(f'{method} {url.split(PACKAGE)[-1]} -> {e.code}: {e.read().decode()[:600]}')


def main():
    aab, track, notes = sys.argv[1], sys.argv[2], sys.argv[3]
    if track not in ('internal', 'alpha', 'beta'):
        sys.exit('Yalnızca test kanalları: internal | alpha | beta')
    tok = token()
    edit = call(tok, 'POST', f'{API}/edits', b'{}')['id']
    print('Paket yükleniyor...')
    bundle = call(tok, 'POST', f'{UPLOAD}/edits/{edit}/bundles?uploadType=media',
                  open(aab, 'rb').read(), 'application/octet-stream')
    code = bundle['versionCode']
    print('Yüklendi, sürüm kodu', code)
    call(tok, 'PUT', f'{API}/edits/{edit}/tracks/{track}', json.dumps({
        'track': track,
        'releases': [{
            'versionCodes': [str(code)],
            'status': 'completed',
            'releaseNotes': [{'language': 'tr-TR', 'text': notes}],
        }],
    }).encode())
    call(tok, 'POST', f'{API}/edits/{edit}:commit')
    print(f'Gönderildi: {track} kanalı, sürüm kodu {code}')


if __name__ == '__main__':
    main()
