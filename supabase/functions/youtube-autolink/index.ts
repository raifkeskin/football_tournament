// Turnuvanın YouTube kanalındaki yayınları maçlara bağlar
// (bkz. migration 20261021120000_youtube_autolink.sql).
//
// Cron (youtube_autolink_tick, 5 dk) `x-sync-secret` ile çağırır. Her
// turnuva için kanalın yükleme listesi (son 25 video) YouTube Data API ile
// okunur (istek başına 1 birim; günlük ücretsiz kota 10.000). Eşleşme:
//   1. Başlıkta maç kodu: #LM + maç kimliğinin ilk 6 hanesi (kesin).
//   2. Başlıkta iki takımın adı + yayın saati maça yakın (tek aday ise).
// Maçta zaten "Maç Yayın Linki" varsa eklenmez; bağlanan video
// youtube_video_links'e yazılır ve bir daha işlenmez.
//
// JWT doğrulaması kapalı yayınlanır (`--no-verify-jwt`); yetki secret ile.

import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const API_KEY = Deno.env.get("YOUTUBE_API_KEY") ?? "";
const YT = "https://www.googleapis.com/youtube/v3";
const LIVE_LINK = "Maç Yayın Linki";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function yt(path: string, params: Record<string, string>) {
  const q = new URLSearchParams({ ...params, key: API_KEY });
  const res = await fetch(`${YT}/${path}?${q}`);
  if (!res.ok) throw new Error(`YouTube ${path} ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return await res.json();
}

/** Kanal adresinden UC... kimliği: /channel/, @handle, /user/, yoksa sayfa. */
async function resolveChannelId(url: string): Promise<string | null> {
  let u: URL;
  try {
    u = new URL(url.startsWith("http") ? url : `https://${url}`);
  } catch (_) {
    return null;
  }
  const parts = u.pathname.split("/").filter(Boolean);
  if (parts[0] === "channel" && parts[1]?.startsWith("UC")) return parts[1];
  if (parts[0]?.startsWith("@")) {
    const r = await yt("channels", { part: "id", forHandle: parts[0] });
    if (r.items?.[0]?.id) return r.items[0].id;
  }
  if (parts[0] === "user" && parts[1]) {
    const r = await yt("channels", { part: "id", forUsername: parts[1] });
    if (r.items?.[0]?.id) return r.items[0].id;
  }
  // /c/ad gibi eski adresler: sayfadaki kanal kimliği.
  const page = await fetch(`https://www.youtube.com${u.pathname}`, {
    headers: { "User-Agent": "Mozilla/5.0", Cookie: "SOCS=CAI; CONSENT=YES+" },
  });
  const m = (await page.text()).match(/"externalId":"(UC[\w-]{22})"/);
  return m?.[1] ?? null;
}

/** Türkçe harfleri sadeleştir, küçült, harf/rakam dışını boşluk yap. */
function norm(s: string): string {
  return ` ${s
    .replace(/İ/g, "i").replace(/I/g, "ı")
    .toLowerCase()
    .replace(/ı/g, "i").replace(/ş/g, "s").replace(/ğ/g, "g")
    .replace(/ü/g, "u").replace(/ö/g, "o").replace(/ç/g, "c")
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()} `;
}

// Takım adında ayırt edici olmayan ekler.
const STOP = new Set([
  "master", "masters", "masterler", "masterlar", "veteran", "veteranlar",
  "fk", "sk", "spor", "kulubu", "futbol", "takimi", "sc", "fc",
]);

/** Başlıkta takım geçiyor mu: tam ad, kısa ad ya da tüm ayırt edici kelimeler. */
function teamIn(title: string, name: string, short: string | null): boolean {
  const full = norm(name);
  if (full.trim() && title.includes(full)) return true;
  if (short && norm(short).trim() && title.includes(norm(short))) return true;
  // Rakamlar (kuruluş yılı) zorunlu değil.
  const words = full.trim().split(" ").filter((w) => w.length >= 3 && !STOP.has(w) && !/^\d+$/.test(w));
  return words.length > 0 && words.every((w) => title.includes(` ${w} `));
}

/** Maçın başlama anı (İstanbul, UTC+3); saat yoksa günün 12:00'si. */
function kickoff(date: string, time: string | null): number {
  const t = /^\d{1,2}:\d{2}/.test(time ?? "") ? time!.slice(0, 5).padStart(5, "0") : "12:00";
  return Date.parse(`${date}T${t}:00+03:00`);
}

type Match = {
  id: string;
  match_date: string;
  match_time: string | null;
  home_team_id: string;
  away_team_id: string;
};

async function syncLeague(league: { id: string; youtube_url: string; youtube_channel_id: string | null }) {
  let channelId = league.youtube_channel_id;
  if (!channelId) {
    channelId = await resolveChannelId(league.youtube_url);
    if (!channelId) return { league: league.id, error: "kanal bulunamadı" };
    await admin.from("leagues").update({ youtube_channel_id: channelId }).eq("id", league.id);
  }

  const today = new Date(Date.now() + 3 * 3600_000).toISOString().slice(0, 10);
  const day = (d: number) => new Date(Date.parse(today) + d * 86400_000).toISOString().slice(0, 10);
  const { data: matches } = await admin
    .from("matches")
    .select("id, match_date, match_time, home_team_id, away_team_id")
    .eq("league_id", league.id)
    .is("deleted_at", null)
    .gte("match_date", day(-2))
    .lte("match_date", day(1));
  if (!matches?.length) return { league: league.id, linked: 0 };

  const { data: existing } = await admin
    .from("match_media")
    .select("match_id")
    .eq("media_type", LIVE_LINK)
    .in("match_id", matches.map((m) => m.id));
  const hasLink = new Set((existing ?? []).map((r) => r.match_id));
  const open = (matches as Match[]).filter((m) => !hasLink.has(m.id));
  if (!open.length) return { league: league.id, linked: 0 };

  const teamIds = [...new Set(open.flatMap((m) => [m.home_team_id, m.away_team_id]))];
  const { data: teams } = await admin.from("teams").select("id, name, short_name").in("id", teamIds);
  const team = new Map((teams ?? []).map((t) => [t.id, t]));

  // Kanalın yükleme listesi: UC... → UU...
  const list = await yt("playlistItems", {
    part: "contentDetails",
    playlistId: `UU${channelId.slice(2)}`,
    maxResults: "25",
  });
  const ids: string[] = (list.items ?? []).map((i: any) => i.contentDetails?.videoId).filter(Boolean);
  if (!ids.length) return { league: league.id, linked: 0 };
  const { data: seen } = await admin.from("youtube_video_links").select("video_id").in("video_id", ids);
  const seenIds = new Set((seen ?? []).map((r) => r.video_id));
  const fresh = ids.filter((id) => !seenIds.has(id));
  if (!fresh.length) return { league: league.id, linked: 0 };

  const vids = await yt("videos", { part: "snippet,liveStreamingDetails", id: fresh.join(",") });
  let linked = 0;
  for (const v of vids.items ?? []) {
    const rawTitle: string = v.snippet?.title ?? "";
    const title = norm(rawTitle);
    const at = Date.parse(
      v.liveStreamingDetails?.actualStartTime ??
        v.liveStreamingDetails?.scheduledStartTime ??
        v.snippet?.publishedAt ?? "",
    );

    let match: Match | undefined;
    let by: "code" | "teams" = "code";
    const code = rawTitle.match(/#LM([0-9a-f]{6})\b/i)?.[1]?.toLowerCase();
    if (code) {
      match = open.find((m) => m.id.replace(/-/g, "").startsWith(code));
    } else {
      by = "teams";
      // İki takım da başlıkta + yayın, başlama saatinden 4 saat önce ile
      // 30 saat sonrası arasında; birden fazla aday varsa en yakını.
      const cands = open
        .filter((m) => {
          const h = team.get(m.home_team_id), a = team.get(m.away_team_id);
          return h && a && teamIn(title, h.name, h.short_name) && teamIn(title, a.name, a.short_name);
        })
        .map((m) => ({ m, d: at - kickoff(m.match_date, m.match_time) }))
        .filter((c) => !Number.isNaN(c.d) && c.d > -4 * 3600_000 && c.d < 30 * 3600_000)
        .sort((x, y) => Math.abs(x.d) - Math.abs(y.d));
      match = cands[0]?.m;
    }
    if (!match) continue;

    const { error } = await admin.from("match_media").insert({
      match_id: match.id,
      media_type: LIVE_LINK,
      url: `https://www.youtube.com/watch?v=${v.id}`,
    });
    if (error) continue;
    await admin.from("youtube_video_links").insert({
      video_id: v.id,
      league_id: league.id,
      match_id: match.id,
      title: rawTitle,
      matched_by: by,
    });
    open.splice(open.indexOf(match), 1);
    linked++;
  }
  return { league: league.id, linked };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST bekleniyor." }, 405);
  const { data: s } = await admin
    .from("app_private_settings")
    .select("value")
    .eq("key", "youtube_sync_secret")
    .maybeSingle();
  if (!s?.value || s.value !== (req.headers.get("x-sync-secret") ?? "")) {
    return json({ error: "Yetkisiz." }, 401);
  }
  if (!API_KEY) return json({ skipped: "YOUTUBE_API_KEY yok" });

  const { data: leagues, error } = await admin
    .from("leagues")
    .select("id, youtube_url, youtube_channel_id")
    .not("youtube_url", "is", null);
  if (error) return json({ error: error.message }, 500);
  const results = [];
  for (const l of leagues ?? []) {
    if (!l.youtube_url?.trim()) continue;
    try {
      results.push(await syncLeague(l));
    } catch (e) {
      results.push({ league: l.id, error: String(e) });
    }
  }
  return json({ results });
});
