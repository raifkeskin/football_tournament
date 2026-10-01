#!/usr/bin/env python3
"""ImgBB'deki resimleri Supabase Storage `media` bucket'ına taşır.

Admin hesabıyla giriş yapar (storage yetki kuralları admin'e izin verir),
her i.ibb.co linkini indirir, yükler ve satırı yeni linkle günceller.
ImgBB'deki asıl dosyalar silinmez (silme linkleri saklanmadı).

Kullanım:
  python3 scripts/migrate_imgbb_to_storage.py            # sadece rapor
  python3 scripts/migrate_imgbb_to_storage.py --apply    # taşı

Gizli bilgiler ~/.config/football_tournament/admin.env içinden okunur;
anon key lib/core/config/app_config.dart içindeki varsayılandan alınır.
"""
import json
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUCKET = "media"
# tablo, birincil anahtar, kolon, klasör
TARGETS = [
    ("teams", "id", "logo_url", "teams"),
    ("leagues", "id", "logo_url", "leagues"),
    ("players", "id", "photo_url", "players"),
    ("news", "id", "image_url", "news"),
    ("match_media", "id", "url", "matches"),
]


def read_config():
    src = open(os.path.join(ROOT, "lib/core/config/app_config.dart")).read()

    def default_of(name):
        m = re.search(name + r"'.*?defaultValue:\s*'([^']+)'", src, re.S)
        return m.group(1) if m else None

    env = {}
    with open(os.path.expanduser("~/.config/football_tournament/admin.env")) as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                env[k] = v.strip("'\"")
    return (
        os.environ.get("SUPABASE_URL") or default_of("SUPABASE_URL"),
        os.environ.get("SUPABASE_ANON_KEY") or default_of("SUPABASE_ANON_KEY"),
        env["ADMIN_EMAIL"],
        env["ADMIN_PASSWORD"],
    )


def request(method, url, headers, body=None):
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
        return r.status, data


def main():
    apply = "--apply" in sys.argv
    base, anon, email, password = read_config()
    _, data = request(
        "POST",
        f"{base}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Content-Type": "application/json"},
        json.dumps({"email": email, "password": password}).encode(),
    )
    token = json.loads(data)["access_token"]
    auth = {"apikey": anon, "Authorization": f"Bearer {token}"}

    total = 0
    for table, pk, col, folder in TARGETS:
        _, data = request(
            "GET",
            f"{base}/rest/v1/{table}?select={pk},{col}&{col}=ilike.*ibb.co*",
            auth,
        )
        rows = json.loads(data)
        for row in rows:
            old = row[col]
            total += 1
            print(f"{table}.{col} {row[pk]}: {old}")
            if not apply:
                continue
            _, img = request("GET", old, {"User-Agent": "Mozilla/5.0"})
            ext = old.rsplit(".", 1)[-1].lower().split("?")[0]
            ext = "jpg" if ext in ("jpeg", "") or len(ext) > 4 else ext
            ctype = {"png": "image/png", "webp": "image/webp", "gif": "image/gif"}.get(
                ext, "image/jpeg"
            )
            path = f"{folder}/{int(time.time() * 1000)}_imgbb.{ext}"
            request(
                "POST",
                f"{base}/storage/v1/object/{BUCKET}/{path}",
                {**auth, "Content-Type": ctype, "Cache-Control": "max-age=31536000"},
                img,
            )
            new = f"{base}/storage/v1/object/public/{BUCKET}/{path}"
            request(
                "PATCH",
                f"{base}/rest/v1/{table}?{pk}=eq.{row[pk]}",
                {**auth, "Content-Type": "application/json", "Prefer": "return=minimal"},
                json.dumps({col: new}).encode(),
            )
            print(f"  -> {new} ({len(img) // 1024} KB)")
    print(f"\n{total} resim {'taşındı' if apply else 'taşınacak (rapor modu)'}.")


if __name__ == "__main__":
    main()
