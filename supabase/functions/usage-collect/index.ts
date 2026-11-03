// Saatlik trafik toplama (cron usage_collect_tick, her saatin 7. dakikası).
//
// Supabase yönetim API'sinin kayıt sorgusuyla (analytics/endpoints/logs,
// ClickHouse SQL) biten saatlerin edge_logs kayıtlarından yanıt boyutları
// türe ve önbellek durumuna göre toplanır, usage_hourly'ye yazılır. Eksik
// kalan saatler (en çok son 24) de doldurulur. Ardından usage_alarm_check()
// kotanın %70'ini geçen kalem için Telegram uyarısı yollar.
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
GROUP BY kind, cache`;

async function hourRows(start: Date) {
  const end = new Date(start.getTime() + 36e5);
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
    hour: start.toISOString(),
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
  // Biten son saat ve ondan geriye en çok 24 saat; yazılmış olanlar atlanır.
  const now = new Date();
  const last = new Date(Math.floor(now.getTime() / 36e5) * 36e5 - 36e5);
  const { data: done } = await admin.from("usage_hourly").select("hour")
    .gte("hour", new Date(last.getTime() - 23 * 36e5).toISOString());
  const have = new Set((done ?? []).map((d) => new Date(d.hour).getTime()));
  const written: string[] = [];
  const errors: string[] = [];
  for (let i = 23; i >= 0; i--) {
    const h = new Date(last.getTime() - i * 36e5);
    if (have.has(h.getTime())) continue;
    try {
      const rows = await hourRows(h);
      // Kaydı olmayan saat de işaretlensin diye boş satır.
      const out = rows.length ? rows : [{ hour: h.toISOString(), kind: "diger", cache: "", requests: 0, bytes: 0 }];
      const { error } = await admin.from("usage_hourly").upsert(out);
      if (error) throw error;
      written.push(h.toISOString());
    } catch (e) {
      errors.push(`${h.toISOString()}: ${e}`);
    }
  }
  await admin.rpc("usage_alarm_check");
  return new Response(JSON.stringify({ written, errors }), {
    headers: { "Content-Type": "application/json" },
  });
});
