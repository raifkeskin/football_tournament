#!/bin/bash
# Gece çalışması: verilen saate kadar bekler (Mac uyanık kalır), tam testi
# başlatır, test boyunca 30 sn'de bir veritabanı bağlantı sayılarını kaydeder.
set -uo pipefail
cd "$(dirname "$0")/../.."
AT="${1:-03:00}"
OUT=tool/loadtest/results
mkdir -p "$OUT"
target=$(date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) $AT" +%s)
now=$(date +%s)
[ "$target" -le "$now" ] && target=$((target + 86400))
echo "Bekleniyor: $(date -r "$target") ($(( (target - now) / 60 )) dk)"
caffeinate -dimsu -w $$ &
sleep $((target - now))
DB="$(head -1 ~/.config/football_tournament/db.env)"
STAMP=$(date +%Y%m%d-%H%M)
(
  while true; do
    psql "$DB" -Atc "select now()::time(0), count(*), count(*) filter (where state='active'), count(*) filter (where application_name ilike '%realtime%'), count(*) filter (where usename='authenticator') from pg_stat_activity" 2>&1
    sleep 30
  done
) > "$OUT/db-sample-$STAMP.txt" &
SAMPLER=$!
./tool/loadtest/run.sh full
kill $SAMPLER 2>/dev/null
echo "Bitti: $(date)"
