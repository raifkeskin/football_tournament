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

# Derleme kimliği: hata kayıtlarında görünür; web yığın izi bu kimliğin
# kaynak haritasıyla çözülür (tool/decode_errors.dart).
BUILD_ID="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain -- lib pubspec.yaml)" ]]; then
  BUILD_ID="${BUILD_ID}-d$(date +%m%d%H%M)"
fi

echo "==> flutter build web --release (BUILD_ID=$BUILD_ID)"
flutter build web --release --source-maps --dart-define=BUILD_ID="$BUILD_ID"

# Kaynak haritası yayına konmaz (kaynak kodu açığa çıkarır); yerelde saklanır.
mkdir -p "build_maps/$BUILD_ID"
find build/web -name '*.js.map' -exec mv {} "build_maps/$BUILD_ID/" \;

# Statik sayfalar (katilim.html, panel.html, teklif.html, sozlesme.html) uygulamanın herkese açık anon anahtarını
# kullanır; anahtar tek yerde (app_config.dart) durur, burada yerleştirilir.
ANON_KEY="$(grep -A2 "'SUPABASE_ANON_KEY'" lib/core/config/app_config.dart | grep -oE "eyJ[A-Za-z0-9._-]+")"
if [[ -z "$ANON_KEY" ]]; then
  echo "Anon anahtar bulunamadı (app_config.dart)." >&2
  exit 1
fi
for f in build/web/katilim.html build/web/panel.html build/web/teklif.html build/web/sozlesme.html; do
  sed -i '' "s|__SUPABASE_ANON_KEY__|$ANON_KEY|g" "$f"
done

echo "==> firebase deploy --only hosting"
firebase deploy --only hosting

echo "==> Yayın tamamlandı."
