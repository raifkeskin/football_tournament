#!/usr/bin/env python3
"""App Store Connect API: iOS sürüm kaydı, yenilikler metni, derleme seçimi
ve incelemeye gönderme.

Kullanım:
  python3 -I tool/asc.py status
      Uygulama, sürümler ve son derlemeler.
  python3 -I tool/asc.py prepare <sürüm> <derleme> "<yenilikler>"
      Sürümü açar (yoksa), derlemeyi seçer, tr yenilikler metnini yazar.
  python3 -I tool/asc.py screenshots <sürüm> <klasör>
      Ekran görüntüsü setlerini klasördeki iphone63_N/ipad13_N.png ile değiştirir.
  python3 -I tool/asc.py submit <sürüm>
      Hazırlanan sürümü incelemeye gönderir (yalnız kullanıcı onayıyla).

Kimlik: ~/.config/football_tournament/asc.env (ASC_KEY_ID, ASC_ISSUER_ID) ve
AuthKey_<KEY_ID>.p8. JWT openssl ile imzalanır (ek Python paketi gerekmez).
"""
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_ID = 'com.ligmasasi.app'
API = 'https://api.appstoreconnect.apple.com/v1'
CONF = os.path.expanduser('~/.config/football_tournament')


def _env():
    out = {}
    for line in open(os.path.join(CONF, 'asc.env')):
        if '=' in line:
            k, v = line.strip().split('=', 1)
            out[k] = v
    return out


def _der_to_raw(der):
    """ECDSA DER imzasını JWT'nin istediği 64 baytlık r||s biçimine çevirir."""
    i = 2
    if der[1] & 0x80:
        i += der[1] & 0x7F

    def read_int(j):
        assert der[j] == 0x02
        n = der[j + 1]
        return der[j + 2:j + 2 + n], j + 2 + n

    r, i = read_int(i)
    s, _ = read_int(i)
    return r.lstrip(b'\x00').rjust(32, b'\x00') + s.lstrip(b'\x00').rjust(32, b'\x00')


def token():
    env = _env()
    kid = env['ASC_KEY_ID']
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b'=')
    now = int(time.time())
    head = b64(json.dumps({'alg': 'ES256', 'kid': kid, 'typ': 'JWT'}).encode())
    claim = b64(json.dumps({
        'iss': env['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1100,
        'aud': 'appstoreconnect-v1',
    }).encode())
    msg = head + b'.' + claim
    key = os.path.join(CONF, f'AuthKey_{kid}.p8')
    with tempfile.NamedTemporaryFile() as f:
        f.write(msg)
        f.flush()
        der = subprocess.run(
            ['openssl', 'dgst', '-sha256', '-sign', key, f.name],
            check=True, capture_output=True,
        ).stdout
    return (msg + b'.' + b64(_der_to_raw(der))).decode()


def call(method, path, body=None, params=None):
    url = path if path.startswith('http') else API + path
    if params:
        url += '?' + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, method=method)
    req.add_header('Authorization', 'Bearer ' + token())
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, data) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            errs = json.loads(detail).get('errors', [])
            detail = '; '.join(f"{x.get('title')}: {x.get('detail')}" for x in errs)
        except ValueError:
            pass
        sys.exit(f'HTTP {e.code} {method} {path}: {detail}')


def app_id():
    d = call('GET', '/apps', params={'filter[bundleId]': BUNDLE_ID})
    if not d['data']:
        sys.exit('Uygulama bulunamadı: ' + BUNDLE_ID)
    return d['data'][0]['id']


def versions(aid):
    return call('GET', f'/apps/{aid}/appStoreVersions',
                params={'filter[platform]': 'IOS', 'limit': 10})['data']


def builds(aid, version=None):
    params = {'filter[app]': aid, 'sort': '-uploadedDate', 'limit': 10}
    if version:
        params['filter[version]'] = version
    return call('GET', '/builds', params=params)['data']


def status():
    aid = app_id()
    print('Uygulama:', aid)
    for v in versions(aid):
        a = v['attributes']
        print(f"  sürüm {a['versionString']}: {a['appStoreState']} "
              f"(yayın: {a.get('releaseType')})")
    for b in builds(aid):
        a = b['attributes']
        print(f"  derleme {a['version']}: {a['processingState']} "
              f"{a['uploadedDate'][:16]}")


def prepare(version, build_no, notes):
    aid = app_id()
    v = next((x for x in versions(aid)
              if x['attributes']['versionString'] == version), None)
    # Apple tek düzenlenebilir sürüme izin verir: gönderilmemiş eski kayıt
    # varsa yeni numarayla yeniden adlandırılır.
    editable = ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED',
                'METADATA_REJECTED')
    if v is None:
        v = next((x for x in versions(aid)
                  if x['attributes']['appStoreState'] in editable), None)
        if v is not None:
            old = v['attributes']['versionString']
            v = call('PATCH', f"/appStoreVersions/{v['id']}", {'data': {
                'type': 'appStoreVersions', 'id': v['id'],
                'attributes': {'versionString': version},
            }})['data']
            print(f'Sürüm kaydı {old} → {version} yapıldı')
    if v is None:
        v = call('POST', '/appStoreVersions', {'data': {
            'type': 'appStoreVersions',
            'attributes': {'platform': 'IOS', 'versionString': version,
                           'releaseType': 'AFTER_APPROVAL'},
            'relationships': {'app': {'data': {'type': 'apps', 'id': aid}}},
        }})['data']
        print('Sürüm açıldı:', version)
    else:
        print('Sürüm mevcut:', version, v['attributes']['appStoreState'])
    vid = v['id']

    b = next((x for x in builds(aid, build_no)), None)
    if b is None:
        sys.exit(f'Derleme {build_no} bulunamadı (henüz işlenmemiş olabilir).')
    if b['attributes']['processingState'] != 'VALID':
        sys.exit(f"Derleme {build_no} hazır değil: "
                 f"{b['attributes']['processingState']}")
    call('PATCH', f'/appStoreVersions/{vid}/relationships/build',
         {'data': {'type': 'builds', 'id': b['id']}})
    print('Derleme seçildi:', build_no)

    locs = call('GET', f'/appStoreVersions/{vid}/appStoreVersionLocalizations')['data']
    if not locs:
        sys.exit('Sürümde dil kaydı yok.')
    for loc in locs:
        call('PATCH', f"/appStoreVersionLocalizations/{loc['id']}", {'data': {
            'type': 'appStoreVersionLocalizations', 'id': loc['id'],
            'attributes': {'whatsNew': notes},
        }})
        print('Yenilikler yazıldı:', loc['attributes']['locale'])


SHOT_TYPES = {'iphone63': 'APP_IPHONE_61', 'iphone69': 'APP_IPHONE_67',
              'ipad13': 'APP_IPAD_PRO_3GEN_129'}


def _upload_shot(set_id, path):
    data = open(path, 'rb').read()
    shot = call('POST', '/appScreenshots', {'data': {
        'type': 'appScreenshots',
        'attributes': {'fileName': os.path.basename(path), 'fileSize': len(data)},
        'relationships': {'appScreenshotSet': {
            'data': {'type': 'appScreenshotSets', 'id': set_id}}},
    }})['data']
    for op in shot['attributes']['uploadOperations']:
        req = urllib.request.Request(op['url'], method=op['method'],
                                     data=data[op['offset']:op['offset'] + op['length']])
        for h in op['requestHeaders']:
            req.add_header(h['name'], h['value'])
        urllib.request.urlopen(req).read()
    call('PATCH', f"/appScreenshots/{shot['id']}", {'data': {
        'type': 'appScreenshots', 'id': shot['id'],
        'attributes': {'uploaded': True,
                       'sourceFileChecksum': hashlib.md5(data).hexdigest()},
    }})
    return shot['id']


def screenshots(version, folder):
    """<önek>_<sıra>.png dosyalarıyla (iphone63_1.png …) setleri değiştirir."""
    aid = app_id()
    v = next((x for x in versions(aid)
              if x['attributes']['versionString'] == version), None)
    if v is None:
        sys.exit('Sürüm yok: ' + version)
    files = sorted(f for f in os.listdir(folder) if f.endswith('.png'))
    for loc in call('GET', f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")['data']:
        sets = {s['attributes']['screenshotDisplayType']: s['id'] for s in call(
            'GET', f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")['data']}
        for prefix, dtype in SHOT_TYPES.items():
            mine = sorted((f for f in files if f.startswith(prefix + '_')),
                          key=lambda f: int(f.rsplit('_', 1)[1].split('.')[0]))
            if not mine:
                continue
            sid = sets.get(dtype)
            if sid is None:
                sid = call('POST', '/appScreenshotSets', {'data': {
                    'type': 'appScreenshotSets',
                    'attributes': {'screenshotDisplayType': dtype},
                    'relationships': {'appStoreVersionLocalization': {
                        'data': {'type': 'appStoreVersionLocalizations', 'id': loc['id']}}},
                }})['data']['id']
            for old in call('GET', f'/appScreenshotSets/{sid}/appScreenshots')['data']:
                call('DELETE', f"/appScreenshots/{old['id']}")
            ids = [_upload_shot(sid, os.path.join(folder, f)) for f in mine]
            call('PATCH', f'/appScreenshotSets/{sid}/relationships/appScreenshots',
                 {'data': [{'type': 'appScreenshots', 'id': i} for i in ids]})
            print(f"{loc['attributes']['locale']} {dtype}: {len(ids)} görüntü yüklendi")


def submit(version):
    aid = app_id()
    v = next((x for x in versions(aid)
              if x['attributes']['versionString'] == version), None)
    if v is None:
        sys.exit('Sürüm yok: ' + version)
    sub = call('POST', '/reviewSubmissions', {'data': {
        'type': 'reviewSubmissions',
        'attributes': {'platform': 'IOS'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': aid}}},
    }})['data']
    call('POST', '/reviewSubmissionItems', {'data': {
        'type': 'reviewSubmissionItems',
        'relationships': {
            'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sub['id']}},
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': v['id']}},
        },
    }})
    call('PATCH', f"/reviewSubmissions/{sub['id']}", {'data': {
        'type': 'reviewSubmissions', 'id': sub['id'],
        'attributes': {'submitted': True},
    }})
    print('İncelemeye gönderildi:', version)


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'status'
    if cmd == 'status':
        status()
    elif cmd == 'prepare' and len(sys.argv) == 5:
        prepare(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == 'screenshots' and len(sys.argv) == 4:
        screenshots(sys.argv[2], sys.argv[3])
    elif cmd == 'submit' and len(sys.argv) == 3:
        submit(sys.argv[2])
    else:
        sys.exit(__doc__)
