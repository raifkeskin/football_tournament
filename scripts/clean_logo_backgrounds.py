#!/usr/bin/env python3
"""Takım ve turnuva logolarındaki beyaz arka planı temizler.

Uygulamadaki algoritmayı (lib/core/utils/logo_background.dart) yükleme
özelliğinden önce eklenmiş logolara uygular: köşeleri opak ve beyaza yakın
olan logolar temizlenip PNG olarak yeniden yüklenir, satır yeni linkle
güncellenir. Eski dosyalar silinmez.

Kullanım:
  python3 scripts/clean_logo_backgrounds.py --out DİZİN            # rapor + önizleme
  python3 scripts/clean_logo_backgrounds.py --out DİZİN --apply    # yükle ve güncelle

Giriş bilgileri migrate_imgbb_to_storage.py ile aynı yerden okunur.
"""
import json
import os
import subprocess
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from migrate_imgbb_to_storage import BUCKET, ROOT, read_config, request  # noqa: E402

TARGETS = [("teams", "teams"), ("leagues", "leagues")]


def main():
    apply = "--apply" in sys.argv
    out_dir = sys.argv[sys.argv.index("--out") + 1]
    os.makedirs(out_dir, exist_ok=True)
    base, anon, email, password = read_config()
    _, data = request(
        "POST",
        f"{base}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Content-Type": "application/json"},
        json.dumps({"email": email, "password": password}).encode(),
    )
    token = json.loads(data)["access_token"]
    auth = {"apikey": anon, "Authorization": f"Bearer {token}"}

    cleaned = 0
    for table, folder in TARGETS:
        _, data = request(
            "GET", f"{base}/rest/v1/{table}?select=id,name,logo_url&logo_url=not.is.null", auth
        )
        for row in json.loads(data):
            url = (row["logo_url"] or "").strip()
            if not url:
                continue
            safe = f"{table}_{row['id']}"
            src = os.path.join(out_dir, safe + ".src")
            png = os.path.join(out_dir, safe + ".png")
            preview = os.path.join(out_dir, safe + "_preview.png")
            try:
                _, img = request("GET", url, {"User-Agent": "Mozilla/5.0"})
            except Exception as e:  # noqa: BLE001
                print(f"{table} {row['name']}: indirilemedi ({e})")
                continue
            open(src, "wb").write(img)
            res = subprocess.run(
                ["dart", "run", "scripts/clean_logo.dart", src, png, preview],
                cwd=ROOT, capture_output=True, text=True,
            )
            status = res.stdout.strip().splitlines()[-1] if res.stdout.strip() else "error"
            if status != "clean":
                if status != "skip":
                    print(f"{table} {row['name']}: hata {res.stderr[-300:]}")
                continue
            cleaned += 1
            print(f"{table} {row['name']}: temizlenecek -> {preview}")
            if not apply:
                continue
            path = f"{folder}/{int(time.time() * 1000)}_clean.png"
            request(
                "POST",
                f"{base}/storage/v1/object/{BUCKET}/{path}",
                {**auth, "Content-Type": "image/png", "Cache-Control": "max-age=31536000"},
                open(png, "rb").read(),
            )
            new = f"{base}/storage/v1/object/public/{BUCKET}/{path}"
            request(
                "PATCH",
                f"{base}/rest/v1/{table}?id=eq.{urllib.parse.quote(str(row['id']))}",
                {**auth, "Content-Type": "application/json", "Prefer": "return=minimal"},
                json.dumps({"logo_url": new}).encode(),
            )
            print(f"  -> {new}")
    print(f"\n{cleaned} logo {'temizlendi' if apply else 'temizlenecek (rapor modu)'}.")


if __name__ == "__main__":
    main()
