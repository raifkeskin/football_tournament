#!/usr/bin/env bash
# Web sürümünü derleyip Firebase Hosting'e yayınlar.
# Adımlar sırayla çalışır; biri hata verirse script durur.
#
# Kullanım:
#   ./scripts/deploy_web.sh          # tam temizlikle
#   ./scripts/deploy_web.sh --fast   # flutter clean atlanır (daha hızlı)
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" != "--fast" ]]; then
  echo "==> flutter clean"
  flutter clean
fi

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web --release"
flutter build web --release

echo "==> firebase deploy --only hosting"
firebase deploy --only hosting

echo "==> Yayın tamamlandı."
