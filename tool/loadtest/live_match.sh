#!/bin/bash
# Maç günü testi: ./tool/loadtest/live_match.sh smoke|full [maç_id]
# Demo maçın skoru ve bir olayı 5 sn arayla aynı değerle güncellenir (yalnız
# updated_at değişir; bildirim tetiklenmez); k6 izleyicileri güncellemeyi
# bekler. REFETCH=1: eski uygulama davranışı (her sinyalde yeniden okuma).
set -euo pipefail
cd "$(dirname "$0")/../.."
MODE="${1:-smoke}"
MATCH="${2:-bd1f1a1b-195a-4c6a-83a7-80edbcdd19df}" # Demo Masterlar Ligi
CFG=lib/core/config/app_config.dart
URL=$(grep -A2 "supabaseUrl" "$CFG" | grep -o "https://[a-z0-9]*\.supabase\.co" | head -1)
KEY=$(grep -A3 "supabaseAnonKey" "$CFG" | grep -o "eyJ[A-Za-z0-9._-]*" | head -1)
DB=$(head -1 ~/.config/football_tournament/db.env | sed 's/^[A-Z_]*=//')
# Yalnız demo turnuvanın maçı kabul edilir.
SEASON=$(psql "$DB" -Atc "select season_id from matches where id='$MATCH'")
EVENT=$(psql "$DB" -Atc "select id from match_events where match_id='$MATCH' limit 1")
DEMO=$(psql "$DB" -Atc "select l.is_demo from matches m join seasons s on s.id=m.season_id join leagues l on l.id=s.league_id where m.id='$MATCH'")
[ "$DEMO" = "t" ] || { echo "Maç demo turnuvada değil: $MATCH"; exit 1; }
OUT=tool/loadtest/results
mkdir -p "$OUT"
STAMP=$(date +%Y%m%d-%H%M)
(
  sleep 25
  while kill -0 $$ 2>/dev/null; do
    psql "$DB" -qAtc "update public.matches set home_score = home_score where id = '$MATCH'" >/dev/null 2>&1 || true
    sleep 5
    [ -n "$EVENT" ] && psql "$DB" -qAtc "update public.match_events set minute = minute where id = '$EVENT'" >/dev/null 2>&1 || true
    sleep 5
  done
) &
WRITER=$!
trap 'kill $WRITER 2>/dev/null || true' EXIT
k6 run \
  -e MODE="$MODE" -e MATCH_ID="$MATCH" -e SEASON_ID="$SEASON" -e REFETCH="${REFETCH:-0}" -e SUPABASE_URL="$URL" -e SUPABASE_ANON_KEY="$KEY" \
  --summary-export "$OUT/summary-live-$MODE-$STAMP.json" \
  tool/loadtest/live_match.js 2>&1 | tee "$OUT/log-live-$MODE-$STAMP.txt"
