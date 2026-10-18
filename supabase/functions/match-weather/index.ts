// Maç saatinde hava durumu (bkz. migration 20261023100000_match_weather.sql).
//
// Yalnızca veritabanından `x-sync-secret` ile çağrılır:
// * { action: "geocode", pitch_id? } — sahanın Google Maps linkinden
//   koordinat çıkarır ve pitches'a bir kez yazar (pitch_id yoksa çözülmemiş
//   tüm sahalar). Sıra: linkin kendisindeki koordinat → linkin yönlendiği
//   adresteki yer adı/adres → OpenStreetMap (Photon) → ilçe → Beşiktaş.
// * { action: "refresh" } — weather_due_matches() listesindeki maçlar için
//   OpenWeatherMap 5 gün / 3 saatlik tahmini alır (aynı konum tek istek),
//   başlama saatine en yakın dilimi match_weather'a yazar.
//
// JWT doğrulaması kapalı yayınlanır (`--no-verify-jwt`); yetki burada.
// OPENWEATHER_API_KEY function secret'ı olarak girilir.

import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const OWM_KEY = Deno.env.get("OPENWEATHER_API_KEY") ?? "";
const UA = "LigMasasi/1.0 (raifkeskin@gmail.com)";
const FALLBACK = { lat: 41.043, lng: 29.0094, area: "Beşiktaş", precision: "varsayilan" };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type LatLng = { lat: number; lng: number };

function coordsIn(s: string): LatLng | null {
  const t = decodeURIComponent(s.replace(/\+/g, " "));
  const pats = [
    /!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)/,
    /@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)/,
    /[?&](?:q|query|ll|center|destination)=(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)/,
  ];
  for (const p of pats) {
    const m = t.match(p);
    if (m) {
      const lat = Number(m[1]), lng = Number(m[2]);
      if (Math.abs(lat) <= 90 && Math.abs(lng) <= 180) return { lat, lng };
    }
  }
  return null;
}

/** Linkte yazan yer adı/adres: /maps/place/<metin>/ ya da ?q=<metin>. */
function placeIn(s: string): string | null {
  let u: URL;
  try {
    u = new URL(s);
  } catch (_) {
    return null;
  }
  const m = u.pathname.match(/\/maps\/place\/([^/]+)/);
  if (m) return decodeURIComponent(m[1].replace(/\+/g, " "));
  if (u.hostname.includes("google.") && !u.hostname.startsWith("share")) {
    const q = u.searchParams.get("q") ?? u.searchParams.get("query");
    if (q && !/^-?\d+\.\d+,/.test(q)) return q;
  }
  return null;
}

/** Kısa linki yönlendirmeleri izleyerek çözer (Google sayfasını açmadan). */
async function resolveLink(url: string): Promise<{ coords: LatLng | null; place: string | null }> {
  let cur = url.startsWith("http") ? url : `https://${url}`;
  for (let i = 0; i < 6; i++) {
    const c = coordsIn(cur);
    if (c) return { coords: c, place: placeIn(cur) };
    const p = placeIn(cur);
    if (p) return { coords: null, place: p };
    let next: string | null = null;
    try {
      const u = new URL(cur);
      if (u.hostname.startsWith("consent.")) {
        next = u.searchParams.get("continue");
      } else {
        const res = await fetch(cur, { redirect: "manual", headers: { "User-Agent": "Mozilla/5.0" } });
        await res.body?.cancel();
        const loc = res.headers.get("location");
        if (loc) next = new URL(loc, cur).toString();
      }
    } catch (_) {
      return { coords: null, place: null };
    }
    if (!next) break;
    cur = next;
  }
  return { coords: coordsIn(cur), place: placeIn(cur) };
}

type Geo = { lat: number; lng: number; area: string | null };

/** Karşılaştırma için: küçük harf, Türkçe/şapkalı harfler sade. */
function fold(s: string): string {
  return s.toLocaleLowerCase("tr").replace(/[âà]/g, "a").replace(/ğ/g, "g").replace(/ı/g, "i")
    .replace(/[îì]/g, "i").replace(/ö/g, "o").replace(/ş/g, "s").replace(/[üû]/g, "u").replace(/ç/g, "c");
}

function areaOf(pr: any): string | null {
  return pr.city ?? pr.county ?? pr.district ?? pr.state ?? null;
}

// Photon (komoot, OpenStreetMap verisi; anahtarsız). Nominatim Supabase
// sunucularına 403 verdiği için bu kullanılıyor. Arama Türkiye ile sınırlı;
// ilçe biliniyorsa sonuç o ilçede olmalı (benzer adlı başka yer gelmesin).
const TR_BBOX = "25.6,35.8,44.9,42.2";

async function photon(q: string, district: string | null): Promise<Geo | null> {
  const p = new URLSearchParams({ q, limit: "5", bbox: TR_BBOX });
  await sleep(300);
  const res = await fetch(`https://photon.komoot.io/api/?${p}`, { headers: { "User-Agent": UA } });
  if (!res.ok) return null;
  const feats: any[] = (await res.json())?.features ?? [];
  const want = district ? fold(district) : null;
  for (const f of feats) {
    const pr = f.properties ?? {};
    if (pr.countrycode !== "TR") continue;
    if (want) {
      const where = fold([pr.city, pr.county, pr.district, pr.locality].filter(Boolean).join(" "));
      if (!where.includes(want)) continue;
    }
    const [lng, lat] = f.geometry?.coordinates ?? [];
    if (typeof lat !== "number" || typeof lng !== "number") continue;
    return { lat, lng, area: areaOf(pr) };
  }
  return null;
}

async function reverseArea(c: LatLng): Promise<string | null> {
  const p = new URLSearchParams({ lat: String(c.lat), lon: String(c.lng) });
  const res = await fetch(`https://photon.komoot.io/reverse?${p}`, { headers: { "User-Agent": UA } });
  if (!res.ok) return null;
  const pr = (await res.json())?.features?.[0]?.properties ?? {};
  return areaOf(pr);
}

/** "…, 34418 Kağıthane/İstanbul" → ["Kağıthane", "İstanbul"]. */
function districtOf(place: string): [string, string] | null {
  const m = place.match(/\d{5}\s+([^,/]+)\/([^,]+)/);
  return m ? [m[1].trim(), m[2].trim()] : null;
}

async function geocodePitch(p: { id: string; name: string; city: string | null; location: string | null }) {
  const loc = (p.location ?? "").trim();
  const city = (p.city ?? "").trim() || "İstanbul";
  let out: { lat: number; lng: number; area: string | null; precision: string } | null = null;

  const { coords, place } = loc ? await resolveLink(loc) : { coords: null, place: null };
  if (coords) {
    out = { ...coords, area: await reverseArea(coords), precision: "link" };
  }
  if (!out) {
    // [sorgu, kesinlik, sonucun bulunması gereken ilçe]
    const tries: [string, string, string | null][] = [];
    const d = place ? districtOf(place) : null;
    const dist = d?.[0] ?? null;
    if (place) {
      const parts = place.replace(/No:\s*/gi, "").split(",").map((s) => s.trim()).filter(Boolean)
        .filter((s) => !/^\d{5}\s/.test(s));
      tries.push([`${parts[0]} ${dist ?? city}`, "saha", dist]);
      tries.push([`${p.name} ${dist ?? city}`, "saha", dist]);
      if (parts.length > 1) tries.push([`${parts.slice(1).join(" ")} ${dist ?? city}`, "adres", dist]);
    } else {
      tries.push([`${p.name} ${city}`, "saha", null]);
    }
    if (dist) tries.push([`${dist} ${d![1]}`, "ilce", dist]);
    for (const [q, precision, want] of tries) {
      const g = await photon(q, want);
      if (g) {
        out = { ...g, area: g.area ?? dist, precision };
        break;
      }
    }
  }
  out ??= { ...FALLBACK };
  const { error } = await admin.from("pitches").update({
    lat: out.lat,
    lng: out.lng,
    geo_area: out.area,
    geo_precision: out.precision,
    geo_location: p.location,
  }).eq("id", p.id);
  if (error) throw error;
  return { id: p.id, name: p.name, ...out };
}

async function geocode(pitchId?: string) {
  let q = admin.from("pitches").select("id, name, city, location, geo_location, lat");
  if (pitchId) q = q.eq("id", pitchId);
  const { data, error } = await q;
  if (error) throw error;
  const out = [];
  for (const p of data ?? []) {
    if (!pitchId && p.lat != null && p.location === p.geo_location) continue;
    out.push(await geocodePitch(p));
  }
  return out;
}

async function refresh() {
  if (!OWM_KEY) return { skipped: "OPENWEATHER_API_KEY yok" };
  const { data, error } = await admin.rpc("weather_due_matches");
  if (error) throw error;
  const groups = new Map<string, any[]>();
  for (const r of data ?? []) {
    const k = `${Number(r.lat).toFixed(2)},${Number(r.lng).toFixed(2)}`;
    groups.set(k, [...(groups.get(k) ?? []), r]);
  }
  const rows = [];
  for (const [k, matches] of groups) {
    const [lat, lng] = k.split(",");
    const p = new URLSearchParams({ lat, lon: lng, units: "metric", lang: "tr", appid: OWM_KEY });
    const res = await fetch(`https://api.openweathermap.org/data/2.5/forecast?${p}`);
    if (!res.ok) throw new Error(`OpenWeatherMap ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const list: any[] = (await res.json()).list ?? [];
    for (const m of matches) {
      const ko = Date.parse(m.kickoff_at) / 1000;
      let best: any = null;
      for (const it of list) {
        if (!best || Math.abs(it.dt - ko) < Math.abs(best.dt - ko)) best = it;
      }
      if (!best || Math.abs(best.dt - ko) > 3 * 3600) continue;
      const w = best.weather?.[0] ?? {};
      rows.push({
        match_id: m.match_id,
        pitch_id: m.pitch_id,
        kickoff_at: m.kickoff_at,
        slot_at: new Date(best.dt * 1000).toISOString(),
        temp: Math.round(best.main.temp * 10) / 10,
        feels_like: Math.round(best.main.feels_like * 10) / 10,
        humidity: best.main.humidity,
        wind_kmh: Math.round((best.wind?.speed ?? 0) * 36) / 10,
        pop: Math.round((best.pop ?? 0) * 100),
        rain_mm: Math.round(((best.rain?.["3h"] ?? 0) + (best.snow?.["3h"] ?? 0)) * 10) / 10,
        code: w.id ?? 800,
        description: w.description ?? null,
        is_day: !String(w.icon ?? "d").endsWith("n"),
        frozen: false,
        updated_at: new Date().toISOString(),
      });
    }
  }
  if (rows.length) {
    const { error: e } = await admin.from("match_weather").upsert(rows);
    if (e) throw e;
  }
  return { locations: groups.size, updated: rows.length };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST bekleniyor." }, 405);
  let body: any = {};
  try {
    body = await req.json();
  } catch (_) {
    // boş gövde
  }
  const given = req.headers.get("x-sync-secret") ?? "";
  const { data: s } = await admin
    .from("app_private_settings")
    .select("value")
    .eq("key", "weather_sync_secret")
    .maybeSingle();
  if (!given || !s?.value || s.value !== given) return json({ error: "Yetkisiz." }, 401);
  try {
    if (body?.action === "geocode") {
      const pitches = await geocode(body?.pitch_id ? String(body.pitch_id) : undefined);
      // Yeni koordinatla bekleyen maçların tahmini hemen gelsin.
      const weather = await refresh();
      return json({ pitches, weather });
    }
    if (body?.action === "refresh") return json(await refresh());
    return json({ error: "Bilinmeyen işlem." }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
