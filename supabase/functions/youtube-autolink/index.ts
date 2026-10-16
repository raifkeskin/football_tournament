// Turnuvanın YouTube kanalındaki yayınları maçlara bağlar
// (bkz. migration 20261021120000_youtube_autolink.sql).
//
// Çağrı biçimleri:
// * Cron (youtube_autolink_tick; maç saatinde 5 dk, sonra saatte bir),
//   `x-sync-secret` ile. "YouTube canlı yayın" aktif her turnuvanın kanalı
//   (son 25 video, YouTube Data API; istek başına 1 birim, günlük ücretsiz
//   kota 10.000) son 2 günün maçlarıyla eşleştirilir:
//     1. Başlıkta maç kodu: #LM + maç kimliğinin ilk 6 hanesi (kesin).
//     2. Başlıkta iki takımın adı + yayın saati maça yakın.
//   Linksiz maça link eklenir. Maçta elle girilmiş başka bir YouTube yayını
//   varsa ve o yayının başlığı bu maça ait görünmüyorsa
//   youtube_link_conflicts'e (Bekleyen Onaylar) yazılır. İşlenen video
//   youtube_video_links'e yazılır ve bir daha işlenmez.
//   Gövde { dry: true, back: N } → hiçbir şey yazmaz, eşleşmeleri döndürür.
// * Uygulama (oturum belirteci; owns_match: admin, kurucu başkan, bölge
//   sorumlusu): { action: "search", match_id } kanaldaki uygun yayınları
//   listeler; { action: "attach", match_id, video_id } maça ekler.
//
// JWT doğrulaması kapalı yayınlanır (`--no-verify-jwt`); yetki burada.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const API_KEY = Deno.env.get("YOUTUBE_API_KEY") ?? "";
const YT = "https://www.googleapis.com/youtube/v3";
const LIVE_LINK = "Maç Yayın Linki";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
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

/** İki kelime arasında en fazla bir harf farkı (ekleme/silme/değiştirme). */
function near(a: string, b: string): boolean {
  if (a === b) return true;
  if (Math.abs(a.length - b.length) > 1) return false;
  let i = 0, j = 0, diff = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      i++; j++;
      continue;
    }
    if (++diff > 1) return false;
    if (a.length > b.length) i++;
    else if (b.length > a.length) j++;
    else { i++; j++; }
  }
  return diff + (a.length - i) + (b.length - j) <= 1;
}

/**
 * Başlıkta takım geçiyor mu: tam ad, kısa ad ya da ayırt edici kelimelerin
 * en az yarısı. 5+ harfli kelimelerde bir harflik yazım hatası tolere edilir
 * ("MATBAAA", "DİNOMA"); "İST. SİVAS" gibi kısaltmalar yarı kuralıyla geçer.
 */
function teamIn(title: string, name: string, short: string | null): boolean {
  const full = norm(name);
  if (full.trim() && title.includes(full)) return true;
  if (short && norm(short).trim() && title.includes(norm(short))) return true;
  // Rakamlar (kuruluş yılı) sayılmaz.
  const words = full.trim().split(" ").filter((w) => w.length >= 3 && !STOP.has(w) && !/^\d+$/.test(w));
  if (!words.length) return false;
  const titleWords = title.trim().split(" ");
  const found = words.filter((w) =>
    titleWords.some((t) => t === w || (w.length >= 5 && near(w, t)))
  ).length;
  return found * 2 >= words.length;
}

/** Maçın başlama anı (İstanbul, UTC+3); saat yoksa günün 12:00'si. */
function kickoff(date: string, time: string | null): number {
  const t = /^\d{1,2}:\d{2}/.test(time ?? "") ? time!.slice(0, 5).padStart(5, "0") : "12:00";
  return Date.parse(`${date}T${t}:00+03:00`);
}

type Match = {
  id: string;
  league_id: string;
  match_date: string;
  match_time: string | null;
  home_team_id: string;
  away_team_id: string;
};
type League = { id: string; youtube_url: string; youtube_channel_id: string | null };
type Team = { id: string; name: string; short_name: string | null };
type Video = { id: string; title: string; at: number };

const MATCH_COLUMNS = "id, league_id, match_date, match_time, home_team_id, away_team_id";

/** youtube.com/watch?v=, /live/, /shorts/, youtu.be/ → video kimliği. */
function videoIdOf(url: string): string | null {
  try {
    const u = new URL(url.trim());
    const host = u.hostname.replace(/^www\.|^m\./, "");
    if (host === "youtu.be") return u.pathname.split("/")[1] || null;
    if (!host.endsWith("youtube.com")) return null;
    const v = u.searchParams.get("v");
    if (v) return v;
    const parts = u.pathname.split("/").filter(Boolean);
    if (["live", "shorts", "embed"].includes(parts[0])) return parts[1] ?? null;
  } catch (_) {
    // geçersiz adres
  }
  return null;
}

/** Turnuvanın kanal kimliği (gerekirse çözülüp kaydedilir). */
async function channelOf(league: League): Promise<string | null> {
  if (league.youtube_channel_id) return league.youtube_channel_id;
  const id = await resolveChannelId(league.youtube_url);
  if (id) await admin.from("leagues").update({ youtube_channel_id: id }).eq("id", league.id);
  return id;
}

/** Kanalın son videoları (yükleme listesi UC… → UU…). */
async function channelVideoIds(channelId: string, max: number): Promise<string[]> {
  const list = await yt("playlistItems", {
    part: "contentDetails",
    playlistId: `UU${channelId.slice(2)}`,
    maxResults: String(max),
  });
  return (list.items ?? []).map((i: any) => i.contentDetails?.videoId).filter(Boolean);
}

/** Başlık + yayın anı (canlıysa gerçek/planlanan başlangıç). En çok 50 kimlik. */
async function videoDetails(ids: string[]): Promise<Video[]> {
  if (!ids.length) return [];
  const r = await yt("videos", { part: "snippet,liveStreamingDetails", id: ids.slice(0, 50).join(",") });
  return (r.items ?? []).map((v: any) => ({
    id: v.id,
    title: v.snippet?.title ?? "",
    at: Date.parse(
      v.liveStreamingDetails?.actualStartTime ??
        v.liveStreamingDetails?.scheduledStartTime ??
        v.snippet?.publishedAt ?? "",
    ),
  }));
}

async function teamsOf(matches: Match[]): Promise<Map<string, Team>> {
  const ids = [...new Set(matches.flatMap((m) => [m.home_team_id, m.away_team_id]))];
  if (!ids.length) return new Map();
  const { data } = await admin.from("teams").select("id, name, short_name").in("id", ids);
  return new Map(((data ?? []) as Team[]).map((t) => [t.id, t]));
}

/** Başlıkta maçın iki takımı da geçiyor mu? */
function titleFits(title: string, m: Match, team: Map<string, Team>): boolean {
  const n = norm(title);
  const h = team.get(m.home_team_id), a = team.get(m.away_team_id);
  return !!h && !!a && teamIn(n, h.name, h.short_name) && teamIn(n, a.name, a.short_name);
}

function codeOf(title: string): string | undefined {
  return title.match(/#LM([0-9a-f]{6})\b/i)?.[1]?.toLowerCase();
}

/** Videonun maçı: önce kod, yoksa iki takım + başlamadan 4 saat önce ile
 * 30 saat sonrası arası; birden fazla aday varsa saate en yakını. */
function pickMatch(v: Video, cands: Match[], team: Map<string, Team>): { m: Match; by: "code" | "teams" } | null {
  const code = codeOf(v.title);
  if (code) {
    const m = cands.find((c) => c.id.replace(/-/g, "").startsWith(code));
    return m ? { m, by: "code" } : null;
  }
  const best = cands
    .filter((m) => titleFits(v.title, m, team))
    .map((m) => ({ m, d: v.at - kickoff(m.match_date, m.match_time) }))
    .filter((c) => !Number.isNaN(c.d) && c.d > -4 * 3600_000 && c.d < 30 * 3600_000)
    .sort((x, y) => Math.abs(x.d) - Math.abs(y.d))[0];
  return best ? { m: best.m, by: "teams" } : null;
}

async function syncLeague(league: League, dry = false, back = 2) {
  const channelId = await channelOf(league);
  if (!channelId) return { league: league.id, error: "kanal bulunamadı" };

  const today = new Date(Date.now() + 3 * 3600_000).toISOString().slice(0, 10);
  const day = (d: number) => new Date(Date.parse(today) + d * 86400_000).toISOString().slice(0, 10);
  const { data: matchRows } = await admin
    .from("matches")
    .select(MATCH_COLUMNS)
    .eq("league_id", league.id)
    .is("deleted_at", null)
    .gte("match_date", day(-back))
    .lte("match_date", day(1));
  const matches = (matchRows ?? []) as Match[];
  if (!matches.length) return { league: league.id, linked: 0 };

  const { data: links } = await admin
    .from("match_media")
    .select("id, match_id, url")
    .eq("media_type", LIVE_LINK)
    .in("match_id", matches.map((m) => m.id));
  const linkOf = new Map((links ?? []).map((r) => [r.match_id as string, r.url as string]));
  const team = await teamsOf(matches);

  const ids = await channelVideoIds(channelId, dry ? 50 : 25);
  if (!ids.length) return { league: league.id, linked: 0 };
  const { data: seen } = await admin.from("youtube_video_links").select("video_id").in("video_id", ids);
  const seenIds = new Set((seen ?? []).map((r) => r.video_id));
  const fresh = ids.filter((id) => dry || !seenIds.has(id));
  if (!fresh.length) return { league: league.id, linked: 0 };
  const vids = await videoDetails(fresh);

  // Elle girilmiş YouTube linkleri: o videoların başlığı (uyuşmazlık için).
  const manualIds = [...new Set([...linkOf.values()].map(videoIdOf).filter((x): x is string => !!x))];
  const manual = new Map((await videoDetails(manualIds.filter((id) => !ids.includes(id)))).map((v) => [v.id, v]));
  for (const v of vids) manual.set(v.id, v);

  let linked = 0, conflicts = 0;
  const report: unknown[] = [];
  const open = [...matches];
  for (const v of vids) {
    const hit = pickMatch(v, open, team);
    if (!hit) continue;
    const { m, by } = hit;
    open.splice(open.indexOf(m), 1);
    const current = linkOf.get(m.id);
    const currentId = current ? videoIdOf(current) : null;
    const currentVideo = currentId ? manual.get(currentId) : undefined;
    // Uyuşmazlık: elle girilen YouTube yayını başka bir video ve başlığı bu
    // maça ait görünmüyor (kopup yeniden başlatılan yayın uyarı vermez).
    const conflict = !!current && !!currentId && currentId !== v.id &&
      !(currentVideo && titleFits(currentVideo.title, m, team));

    if (dry) {
      const h = team.get(m.home_team_id)?.name, a = team.get(m.away_team_id)?.name;
      report.push({
        video: v.id,
        title: v.title,
        at: new Date(v.at).toISOString(),
        match: `${m.match_date} ${m.match_time ?? ""} ${h} - ${a}`,
        by,
        current: current ?? null,
        action: !current ? "link" : currentId === v.id ? "same" : conflict ? "conflict" : "ok",
      });
      continue;
    }

    if (!current) {
      const { error } = await admin.from("match_media").insert({
        match_id: m.id,
        media_type: LIVE_LINK,
        url: `https://www.youtube.com/watch?v=${v.id}`,
      });
      if (error) continue;
      linked++;
    } else if (conflict) {
      const { error } = await admin.from("youtube_link_conflicts").insert({
        match_id: m.id,
        league_id: league.id,
        manual_url: current,
        manual_video_id: currentId,
        manual_title: currentVideo?.title ?? null,
        manual_at: currentVideo && !Number.isNaN(currentVideo.at) ? new Date(currentVideo.at).toISOString() : null,
        auto_video_id: v.id,
        auto_title: v.title,
        auto_at: Number.isNaN(v.at) ? null : new Date(v.at).toISOString(),
      });
      if (!error) conflicts++;
    }
    await admin.from("youtube_video_links").upsert({
      video_id: v.id,
      league_id: league.id,
      match_id: m.id,
      title: v.title,
      matched_by: by,
    });
  }
  return dry ? { league: league.id, report } : { league: league.id, linked, conflicts };
}

/** Uygulama: kullanıcı maçı yönetebiliyor mu (owns_match)? */
async function canManage(req: Request, matchId: string): Promise<boolean> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return false;
  const user = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } } });
  const { data, error } = await user.rpc("owns_match", { p_match_id: matchId });
  return !error && data === true;
}

async function loadMatch(matchId: string) {
  const { data: m } = await admin.from("matches").select(MATCH_COLUMNS).eq("id", matchId).maybeSingle();
  if (!m) return null;
  const { data: l } = await admin
    .from("leagues")
    .select("id, youtube_url, youtube_channel_id, youtube_live")
    .eq("id", m.league_id)
    .maybeSingle();
  return { match: m as Match, league: l };
}

/** "YouTube'da yayını bul": kanalın son 50 videosundan iki takımın adı
 * geçenler (ya da maç kodu), maç saatine yakınlığa göre; en çok 5. */
async function search(matchId: string) {
  const ctx = await loadMatch(matchId);
  if (!ctx) return json({ error: "Maç bulunamadı." }, 404);
  const { match, league } = ctx;
  if (!league?.youtube_live || !league.youtube_url?.trim()) {
    return json({ error: "Bu turnuvada YouTube canlı yayın kapalı." }, 400);
  }
  const channelId = await channelOf(league as League);
  if (!channelId) return json({ error: "Turnuvanın YouTube kanalı bulunamadı." }, 400);
  const team = await teamsOf([match]);
  const vids = await videoDetails(await channelVideoIds(channelId, 50));
  const ko = match.match_date ? kickoff(match.match_date, match.match_time) : NaN;
  const code = match.id.replace(/-/g, "").slice(0, 6);
  const items = vids
    .filter((v) => codeOf(v.title) === code || (!codeOf(v.title) && titleFits(v.title, match, team)))
    .map((v) => ({ v, d: Number.isNaN(ko) || Number.isNaN(v.at) ? Infinity : Math.abs(v.at - ko) }))
    .sort((x, y) => x.d - y.d)
    .slice(0, 5)
    .map(({ v }) => ({
      video_id: v.id,
      title: v.title,
      at: Number.isNaN(v.at) ? null : new Date(v.at).toISOString(),
    }));
  return json({ items });
}

async function attach(matchId: string, videoId: string) {
  if (!/^[\w-]{6,20}$/.test(videoId)) return json({ error: "Geçersiz video." }, 400);
  const ctx = await loadMatch(matchId);
  if (!ctx) return json({ error: "Maç bulunamadı." }, 404);
  const url = `https://www.youtube.com/watch?v=${videoId}`;
  const { data: existing } = await admin
    .from("match_media")
    .select("id")
    .eq("match_id", matchId)
    .eq("media_type", LIVE_LINK)
    .limit(1);
  const { error } = existing?.length
    ? await admin.from("match_media").update({ url }).eq("id", existing[0].id)
    : await admin.from("match_media").insert({ match_id: matchId, media_type: LIVE_LINK, url });
  if (error) return json({ error: error.message }, 500);
  await admin.from("youtube_video_links").upsert({
    video_id: videoId,
    league_id: ctx.match.league_id,
    match_id: matchId,
    title: null,
    matched_by: null,
  });
  return json({ ok: true, url });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST bekleniyor." }, 405);
  let body: any = {};
  try {
    body = await req.json();
  } catch (_) {
    // boş gövde
  }

  const given = req.headers.get("x-sync-secret") ?? "";
  if (!given) {
    if (!API_KEY) return json({ error: "YouTube bağlantısı ayarlı değil." }, 503);
    const matchId = String(body?.match_id ?? "");
    if (!matchId || !(await canManage(req, matchId))) return json({ error: "Yetkiniz yok." }, 403);
    try {
      if (body?.action === "search") return await search(matchId);
      if (body?.action === "attach") return await attach(matchId, String(body?.video_id ?? ""));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
    return json({ error: "Bilinmeyen işlem." }, 400);
  }

  const { data: s } = await admin
    .from("app_private_settings")
    .select("value")
    .eq("key", "youtube_sync_secret")
    .maybeSingle();
  if (!s?.value || s.value !== given) return json({ error: "Yetkisiz." }, 401);
  if (!API_KEY) return json({ skipped: "YOUTUBE_API_KEY yok" });

  const dry = body?.dry === true;
  const back = Math.min(Math.max(Number(body?.back) || 2, 1), 60);
  const { data: leagues, error } = await admin
    .from("leagues")
    .select("id, youtube_url, youtube_channel_id")
    .eq("youtube_live", true)
    .not("youtube_url", "is", null);
  if (error) return json({ error: error.message }, 500);
  const results = [];
  for (const l of (leagues ?? []) as League[]) {
    if (!l.youtube_url?.trim()) continue;
    try {
      results.push(await syncLeague(l, dry, back));
    } catch (e) {
      results.push({ league: l.id, error: String(e) });
    }
  }
  return json({ results });
});
