#!/usr/bin/env python3
"""Dizilişteki dekupe fotoğrafları üretir (yalnız macOS: Apple Vision).

Oyuncu fotoğrafının arka planını siler, yüze göre baş-omuz kırpar, Storage'a
(media/players/cutouts/) yükler ve player_photo_cutouts tablosuna asıl adresle
eşleyerek yazar. Kaynak kırpım 80 px'ten küçükse (uzak/düşük çözünürlük)
dekupe üretilmez; o oyuncu dizilişte daire kalır.

Admin hesabıyla giriş yapar (admin.env); anon key app_config.dart'tan.

  python3 scripts/make_cutouts.py --team <team_id>           # rapor
  python3 scripts/make_cutouts.py --team <team_id> --apply   # üret + yükle
  python3 scripts/make_cutouts.py --all --apply               # eksik olan herkes

Üretilemeyen fotoğraf player_photo_cutout_skips'e sebebiyle yazılır ve sonraki
çalışmalarda atlanır (--retry ile yeniden denenir). Bekleyenler admin
panelindeki "Dekupe Bekleyenler" ekranında görünür.
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from migrate_imgbb_to_storage import read_config, request  # noqa: E402

BUCKET = "media"
MIN_SRC_PX = 80


def build_tool(tmp):
    exe = os.path.join(tmp, "cut")
    subprocess.run(
        ["swiftc", "-O", os.path.join(ROOT, "tool/cutout/cut.swift"), "-o", exe],
        check=True,
    )
    return exe


def main():
    apply = "--apply" in sys.argv
    team = sys.argv[sys.argv.index("--team") + 1] if "--team" in sys.argv else None
    if not team and "--all" not in sys.argv:
        sys.exit("--team <id> ya da --all verin")
    base, anon, email, password = read_config()
    _, data = request(
        "POST",
        f"{base}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Content-Type": "application/json"},
        json.dumps({"email": email, "password": password}).encode(),
    )
    auth = {"apikey": anon, "Authorization": f"Bearer {json.loads(data)['access_token']}"}

    if team:
        _, data = request(
            "GET",
            f"{base}/rest/v1/season_team_players?select=players(name,surname,photo_url)"
            f"&team_id=eq.{team}&is_active=eq.true",
            auth,
        )
        players = [r["players"] for r in json.loads(data) if r.get("players")]
    else:
        _, data = request(
            "GET", f"{base}/rest/v1/players?select=name,surname,photo_url&photo_url=not.is.null", auth
        )
        players = json.loads(data)
    _, data = request("GET", f"{base}/rest/v1/player_photo_cutouts?select=photo_url", auth)
    done = {r["photo_url"] for r in json.loads(data)}
    if "--retry" not in sys.argv:
        _, data = request("GET", f"{base}/rest/v1/player_photo_cutout_skips?select=photo_url", auth)
        done |= {r["photo_url"] for r in json.loads(data)}

    todo = {}
    for p in players:
        url = (p.get("photo_url") or "").strip()
        if url and url not in done:
            todo[url] = f"{p.get('name', '')} {p.get('surname', '')}".strip()
    print(f"{len(todo)} fotoğraf dekupe bekliyor.")
    if not apply or not todo:
        for url, name in todo.items():
            print(f"  {name}")
        return

    made = skipped = 0
    with tempfile.TemporaryDirectory() as tmp:
        exe = build_tool(tmp)
        for url, name in todo.items():
            src = os.path.join(tmp, "in.jpg")
            out = os.path.join(tmp, "out.png")
            _, img = request("GET", url, {"User-Agent": "Mozilla/5.0"})
            open(src, "wb").write(img)
            r = subprocess.run([exe, src, out], capture_output=True, text=True)
            px = next(
                (int(t.split("=")[1]) for t in r.stdout.split() if t.startswith("srcpx=")), 0
            )
            if r.returncode != 0 or "NOFACE" in r.stdout or px < MIN_SRC_PX:
                skipped += 1
                reason = "yüz yok" if "NOFACE" in r.stdout else f"düşük çözünürlük ({px} px)"
                request(
                    "POST",
                    f"{base}/rest/v1/player_photo_cutout_skips?on_conflict=photo_url",
                    {**auth, "Content-Type": "application/json",
                     "Prefer": "resolution=merge-duplicates,return=minimal"},
                    json.dumps({"photo_url": url, "reason": reason}).encode(),
                )
                print(f"  atlandı: {name} ({reason})")
                continue
            path = f"players/cutouts/{hashlib.sha1(url.encode()).hexdigest()[:20]}.png"
            request(
                "POST",
                f"{base}/storage/v1/object/{BUCKET}/{path}",
                {**auth, "Content-Type": "image/png", "Cache-Control": "max-age=31536000"},
                open(out, "rb").read(),
            )
            cut = f"{base}/storage/v1/object/public/{BUCKET}/{path}"
            request(
                "POST",
                f"{base}/rest/v1/player_photo_cutouts?on_conflict=photo_url",
                {**auth, "Content-Type": "application/json",
                 "Prefer": "resolution=merge-duplicates,return=minimal"},
                json.dumps({"photo_url": url, "cutout_url": cut}).encode(),
            )
            made += 1
            print(f"  dekupe: {name} ({px} px, {os.path.getsize(out) // 1024} KB)")
    print(f"\n{made} dekupe yüklendi, {skipped} atlandı.")


if __name__ == "__main__":
    main()
