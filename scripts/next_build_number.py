#!/usr/bin/env python3
"""Sıradaki derleme numarası: App Distribution'daki en yüksek + 1.

Aynı anda birden fazla oturum APK gönderebildiği için numara yerel nottan
değil, dağıtılmış sürümlerden okunur.
Kullanım: flutter build apk --build-number=$(python3 scripts/next_build_number.py) ...
"""
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apk_cleanup import APP, PROJECT, token  # noqa: E402


def main():
    t = token()
    base = f'https://firebaseappdistribution.googleapis.com/v1/projects/{PROJECT}/apps/{APP}/releases'
    best, page = 0, ''
    while True:
        url = base + '?pageSize=100' + (f'&pageToken={page}' if page else '')
        req = urllib.request.Request(url, headers={'Authorization': f'Bearer {t}'})
        r = json.load(urllib.request.urlopen(req))
        for rel in r.get('releases', []):
            v = rel.get('buildVersion', '')
            if v.isdigit():
                best = max(best, int(v))
        page = r.get('nextPageToken', '')
        if not page:
            break
    print(best + 1)


if __name__ == '__main__':
    main()
