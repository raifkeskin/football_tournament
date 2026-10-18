#!/bin/bash
# Maç günü senaryoları: ./tool/loadtest/matchday.sh [HH:MM] [senaryo...]
# Verilen saate kadar bekler, senaryoları sırayla çalıştırır; her birinde
# demo maç(lar)da yazıcı döngüsü ve 15 sn'de bir veritabanı örneklemesi.
# Yazıcı: her 3 sn'de maç satırı ya da bir olay aynı değerle güncellenir;
# her 60 sn'de "gol anı" patlaması (1 sn içinde maç + 3 olay güncellemesi).
set -uo pipefail
cd "$(dirname "$0")/../.."
AT="${1:-now}"; shift || true
SCENS="${*:-live400 spike multi reconnect mixed limit}"
CFG=lib/core/config/app_config.dart
URL=$(grep -A2 "supabaseUrl" "$CFG" | grep -o "https://[a-z0-9]*\.supabase\.co" | head -1)
KEY=$(grep -A3 "supabaseAnonKey" "$CFG" | grep -o "eyJ[A-Za-z0-9._-]*" | head -1)
DB="$(head -1 ~/.config/football_tournament/db.env)"
OUT=tool/loadtest/results
mkdir -p "$OUT"
caffeinate -dimsu -w $$ &

# Demo maçlar (her biri farklı lig/sezon).
M1=170bd5aa-22fb-487e-987a-4188e0a84ef4  # Demo Masterlar Ligi
M2=9c4e9529-83b6-45cf-a2c5-f81d56b3217f  # Demo Okul Kupası
M3=a9b76150-9e2f-4c19-9cab-df99ec6347a3  # Demo Şirketler Halısaha
M4=9a5c35e4-54d9-4c61-af61-69f708a30b6f  # Demo Şirketler Halısaha (2. maç)

triple() { # maç_id -> id|sezon|lig (yalnız demo)
  psql "$DB" -Atc "select m.id||'|'||m.season_id||'|'||s.league_id from matches m join seasons s on s.id=m.season_id join leagues l on l.id=s.league_id where m.id='$1' and l.is_demo"
}

writer() { # süre_sn maç_id...
  local dur=$1; shift
  local ids; ids=$(printf "'%s'," "$@"); ids="{${ids%,}}"
  ids=$(echo "$ids" | tr -d "'")
  psql "$DB" -qAt -v ON_ERROR_STOP=1 >>"$OUT/writer-$STAMP.txt" 2>&1 <<SQL
set statement_timeout = 0;
do \$\$
declare
  ms uuid[] := '$ids';
  stop timestamptz := clock_timestamp() + interval '$dur seconds';
  n int := 0; m uuid; ev uuid; last_burst timestamptz := clock_timestamp();
begin
  -- Yalnız demo maçlar.
  if exists (select 1 from matches x join seasons s on s.id=x.season_id join leagues l on l.id=s.league_id
             where x.id = any(ms) and not l.is_demo) then raise exception 'demo olmayan maç'; end if;
  while clock_timestamp() < stop loop
    foreach m in array ms loop
      if n % 2 = 0 then
        update matches set home_score = home_score where id = m;
      else
        select id into ev from match_events where match_id = m order by random() limit 1;
        update match_events set minute = minute where id = ev;
      end if;
      commit;
    end loop;
    n := n + 1;
    if clock_timestamp() - last_burst > interval '60 seconds' then
      -- Gol anı: maç + 3 olay neredeyse aynı anda.
      foreach m in array ms loop
        update matches set home_score = home_score where id = m; commit;
        for ev in select id from match_events where match_id = m limit 3 loop
          update match_events set minute = minute where id = ev; commit;
        end loop;
      end loop;
      last_burst := clock_timestamp();
      raise notice 'burst %', clock_timestamp();
    end if;
    perform pg_sleep(3); commit; -- yeni işlem: updated_at = gerçek yazma anı
  end loop;
  raise notice 'yazıcı bitti: % tur', n;
end
\$\$;
SQL
}

sampler() {
  while true; do
    psql "$DB" -Atc "select now()::time(0), count(*), count(*) filter (where state='active'), count(*) filter (where application_name ilike '%realtime%'), count(*) filter (where usename='authenticator'), (select round(100*sum(blks_hit)/nullif(sum(blks_hit)+sum(blks_read),0),2) from pg_stat_database) from pg_stat_activity" 2>&1
    sleep 15
  done
}

if [ "$AT" != "now" ]; then
  target=$(date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) $AT" +%s)
  now=$(date +%s)
  [ "$target" -gt "$now" ] && { echo "Bekleniyor: $AT"; sleep $((target - now)); }
fi

dur() { case $1 in smoke) echo 95;; live400) echo 640;; spike) echo 300;; multi) echo 520;; reconnect) echo 440;; mixed) echo 580;; limit) echo 860;; esac; }
for SC in $SCENS; do
  STAMP=$(date +%Y%m%d-%H%M)-$SC
  case $SC in
    multi) IDS="$M1 $M2 $M3 $M4" ;;
    mixed) IDS="$M1 $M2 $M3" ;;
    *) IDS="$M1" ;;
  esac
  MATCHES=""; for i in $IDS; do MATCHES="$MATCHES$(triple $i),"; done
  echo "=== $SC başlıyor $(date +%H:%M:%S) maçlar: $IDS"
  sampler > "$OUT/db-$STAMP.txt" & SAMP=$!
  ( sleep 20; writer "$(dur $SC)" $IDS ) & WR=$!
  k6 run -q -e SCEN="$SC" -e MATCHES="${MATCHES%,}" -e SUPABASE_URL="$URL" -e SUPABASE_ANON_KEY="$KEY" \
    --summary-export "$OUT/summary-$STAMP.json" \
    --out csv="$OUT/metrics-$STAMP.csv.gz" \
    tool/loadtest/matchday.js > "$OUT/log-$STAMP.txt" 2>&1
  RC=$?
  echo "=== $SC bitti $(date +%H:%M:%S) çıkış=$RC"
  kill $SAMP 2>/dev/null; wait $WR 2>/dev/null
  [ "$SC" != "${SCENS##* }" ] && sleep 90 # soğuma
done
echo "TÜMÜ BİTTİ $(date)"
