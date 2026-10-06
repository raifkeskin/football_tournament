#!/usr/bin/env python3
"""Önceden yüklenmiş büyük logo ve oyuncu fotoğraflarını küçültür.

Uygulamadaki yükleme sınırlarını (logo 384 px PNG, fotoğraf 512 px JPEG)
eski dosyalara uygular: küçültülen dosya yeni adla yüklenir, satır yeni
linkle güncellenir. Eski dosyalar silinmez.

Kullanım:
  python3 scripts/shrink_existing_images.py --out DİZİN            # rapor
  python3 scripts/shrink_existing_images.py --out DİZİN --apply    # yükle ve güncelle

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

# (tablo, sütun, klasör, tür)
TARGETS = [
    ("teams", "logo_url", "teams", "logo"),
    ("leagues", "logo_url", "leagues", "logo"),
    ("players", "photo_url", "players", "photo"),
]
MIN_BYTES = 100 * 1024  # bundan küçükler zaten yeterince küçük


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
    ours = f"{base}/storage/v1/object/public/{BUCKET}/"

    before = after = count = 0
    for table, column, folder, kind in TARGETS:
        _, data = request(
            "GET",
            f"{base}/rest/v1/{table}?select=id,{column}&{column}=like.*{urllib.parse.quote(ours)}*",
            auth,
        )
        for row in json.loads(data):
            url = (row[column] or "").strip()
            if not url.startswith(ours):
                continue
            safe = f"{table}_{row['id']}"
            src = os.path.join(out_dir, safe + ".src")
            try:
                _, img = request("GET", url, {"User-Agent": "Mozilla/5.0"})
            except Exception as e:  # noqa: BLE001
                print(f"{table} {row['id']}: indirilemedi ({e})")
                continue
            if len(img) < MIN_BYTES:
                continue
            open(src, "wb").write(img)
            prefix = os.path.join(out_dir, safe)
            res = subprocess.run(
                ["dart", "run", "scripts/shrink_image.dart", src, prefix, kind],
                cwd=ROOT, capture_output=True, text=True,
            )
            status = res.stdout.strip().splitlines()[-1] if res.stdout.strip() else "error"
            if not status.startswith("ok "):
                if status != "skip":
                    print(f"{table} {row['id']}: hata {res.stderr[-300:]}")
                continue
            ext = status.split()[1]
            out = open(f"{prefix}.{ext}", "rb").read()
            count += 1
            before += len(img)
            after += len(out)
            print(f"{table} {row['id']}: {len(img) // 1024} KB -> {len(out) // 1024} KB")
            if not apply:
                continue
            path = f"{folder}/{int(time.time() * 1000)}_s.{ext}"
            request(
                "POST",
                f"{base}/storage/v1/object/{BUCKET}/{path}",
                {
                    **auth,
                    "Content-Type": "image/png" if ext == "png" else "image/jpeg",
                    "Cache-Control": "max-age=31536000",
                },
                out,
            )
            request(
                "PATCH",
                f"{base}/rest/v1/{table}?id=eq.{urllib.parse.quote(str(row['id']))}",
                {**auth, "Content-Type": "application/json", "Prefer": "return=minimal"},
                json.dumps({column: ours + path}).encode(),
            )
    print(
        f"\n{count} dosya: {before // 1024} KB -> {after // 1024} KB "
        f"({'uygulandı' if apply else 'rapor modu'})."
    )


if __name__ == "__main__":
    main()
