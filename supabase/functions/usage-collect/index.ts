// Trafik toplama: gece bir kez (cron usage_collect_tick) ve İstatistikler'deki
// "Şimdi güncelle" (usage_collect_now). Son yazılan saatten şu ana kadarki
// edge_logs kayıtları, saat saat, türe ve önbellek durumuna göre toplanır
// (Supabase yönetim API'si analytics/endpoints/logs, ClickHouse SQL; tek
// sorgu en çok 24 saat). Son saat yarımsa sonraki toplamada tamamlanır.
// Ardından usage_alarm_check() %70'i geçen kalem için Telegram uyarısı yollar.
//
// Gizli ayar: ISTATISTIK_USAGE_TOKEN (yalnız okuma yetkili erişim anahtarı).
// JWT doğrulaması kapalı yayınlanır (`--no-verify-jwt`); çağrı
// `x-sync-secret` = app_private_settings.drive_sync_secret ile yetkilenir.

import { createClient } from "jsr:@supabase/supabase-js@2";

const REF = "qxdjebzszikeslobrozf";
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const SQL = `
SELECT
  toStartOfHour(timestamp) AS hour,
  multiIf(
    log_attributes['request.path'] LIKE '/storage/v1/object/%/clips/%', 'video',
    log_attributes['request.path'] LIKE '/storage/%', 'dosya',
    log_attributes['request.path'] LIKE '/rest/%', 'veri',
    log_attributes['request.path'] LIKE '/realtime/%', 'canli',
    'diger') AS kind,
  log_attributes['response.headers.cf_cache_status'] AS cache,
  count() AS requests,
  sum(toInt64OrZero(log_attributes['response.headers.content_length'])) AS bytes
FROM logs
WHERE source = 'edge_logs'
GROUP BY hour, kind, cache`;

const DAY = 24 * 36e5;

/// Saat başı: "2026-11-02 12:00:00" (UTC) ya da sayısal zaman damgası.
function hourOf(v: unknown): string {
  if (typeof v === "number" || /^\d+$/.test(String(v))) {
    let n = Number(v);
    if (n > 1e15) n = n / 1000; // mikrosaniye
    else if (n < 1e12) n = n * 1000; // saniye
    return new Date(Math.floor(n / 36e5) * 36e5).toISOString();
  }
  const t = String(v).replace(" ", "T");
  return new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(t) ? t : t + "Z").toISOString();
}

async function rows(start: Date, end: Date) {
  const qs = new URLSearchParams({
    sql: SQL,
    iso_timestamp_start: start.toISOString(),
    iso_timestamp_end: end.toISOString(),
  });
  const r = await fetch(
    `https://api.supabase.com/v1/projects/${REF}/analytics/endpoints/logs?${qs}`,
    { headers: { Authorization: `Bearer ${Deno.env.get("ISTATISTIK_USAGE_TOKEN")}` } },
  );
  const j = await r.json();
  if (!r.ok || j.error) throw new Error(`logs ${r.status}: ${JSON.stringify(j.error ?? j)}`);
  return (j.result ?? []).map((x: Record<string, unknown>) => ({
    hour: hourOf(x.hour),
    kind: String(x.kind ?? "diger"),
    cache: String(x.cache ?? ""),
    requests: Number(x.requests ?? 0),
    bytes: Number(x.bytes ?? 0),
  }));
}

Deno.serve(async (req) => {
  const { data: s } = await admin.from("app_private_settings")
    .select("value").eq("key", "drive_sync_secret").maybeSingle();
  if (!s?.value || req.headers.get("x-sync-secret") !== s.value) {
    return new Response("forbidden", { status: 403 });
  }
  // Son yazılan saatten (yarım kalmış olabilir, yeniden sorulur) şu ana;
  // kayıt yoksa son 24 saat. Kayıtlar birkaç gün tutulduğundan en çok 3 gün
  // geriye gidilir; 24 saatlik dilimlerle.
  const now = new Date();
  const { data: lastRow } = await admin.from("usage_hourly").select("hour")
    .order("hour", { ascending: false }).limit(1).maybeSingle();
  let start = lastRow ? new Date(lastRow.hour) : new Date(now.getTime() - DAY);
  start = new Date(Math.max(start.getTime(), now.getTime() - 3 * DAY));
  let count = 0;
  const errors: string[] = [];
  while (start < now) {
    const end = new Date(Math.min(start.getTime() + DAY, now.getTime()));
    try {
      const out = await rows(start, end);
      if (out.length) {
        const { error } = await admin.from("usage_hourly").upsert(out);
        if (error) throw error;
        count += out.length;
      }
    } catch (e) {
      errors.push(String(e));
      break;
    }
    start = end;
  }
  await admin.rpc("usage_alarm_check");
  return new Response(JSON.stringify({ rows: count, errors }), {
    headers: { "Content-Type": "application/json" },
  });
});
