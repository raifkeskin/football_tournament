#!/usr/bin/env bash
# Derlenmiş APK'yı App Tester'a gönderir, sonra son 30 sürüm kalacak şekilde
# eski test APK'larını siler.
# Kullanım: ./scripts/distribute_apk.sh "Sürüm notu"
set -euo pipefail
cd "$(dirname "$0")/.."

firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk \
  --app 1:974894815246:android:5feb335a68c9da9c1bc45f \
  --release-notes "${1:-}" \
  --testers raifkeskin@gmail.com \
  --project football-tournament-c0c05

python3 scripts/apk_cleanup.py 30 || echo "!! APK temizliği yapılamadı (gönderim tamam)."
