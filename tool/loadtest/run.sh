#!/bin/bash
# Yük testi: ./tool/loadtest/run.sh smoke|full
# Supabase adresi ve anahtarı uygulamanın yapılandırmasından okunur.
set -euo pipefail
cd "$(dirname "$0")/../.."
MODE="${1:-smoke}"
CFG=lib/core/config/app_config.dart
URL=$(grep -A2 "supabaseUrl" "$CFG" | grep -o "https://[a-z0-9]*\.supabase\.co" | head -1)
KEY=$(grep -A3 "supabaseAnonKey" "$CFG" | grep -o "eyJ[A-Za-z0-9._-]*" | head -1)
OUT=tool/loadtest/results
mkdir -p "$OUT"
STAMP=$(date +%Y%m%d-%H%M)
k6 run \
  -e MODE="$MODE" -e SUPABASE_URL="$URL" -e SUPABASE_ANON_KEY="$KEY" \
  --summary-export "$OUT/summary-$MODE-$STAMP.json" \
  --out csv="$OUT/metrics-$MODE-$STAMP.csv.gz" \
  tool/loadtest/app_load.js 2>&1 | tee "$OUT/log-$MODE-$STAMP.txt"
