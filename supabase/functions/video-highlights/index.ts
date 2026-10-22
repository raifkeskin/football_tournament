// YZ ile maç videosundaki golleri bulur (Gemini, YouTube linkini doğrudan
// izler; video indirilmez). Bulunan kesitler match_highlights tablosuna
// "onay bekliyor" olarak yazılır.
//
// Maliyeti düşük tutmak için:
//  1. Videoda maçın ve 2. yarının başladığı an sorumludan alınır (isteğe
//     bağlı); verilmezse YZ düşük kare hızıyla kendisi bulur.
//  2. Başlangıç biliniyorsa her gol dakikasının yalnızca ±2 dk'sı taranır;
//     bilinmiyorsa ±10 dk. Maç detayında gol yoksa tüm video taranır.
//  3. Pencereler videonun büyük kısmını kaplıyorsa tek seferde tüm video
//     taranır (tavan).
//  4. Her çağrının token'ı ve maliyeti ai_usage_log'a yazılır. Tahmini
//     maliyet maç başı veya aylık sınırı (app_private_settings) aşıyorsa
//     Gemini'ye hiç gidilmez.
//
// İstek: POST { match_id, kickoff_sec?, second_half_sec? } — kullanıcının
// oturum belirteciyle; yalnızca owns_match() true olanlar (admin, kurucu
// başkan, bölge sorumlusu) çalıştırabilir. İş arka planda sürer; durum
// match_highlight_jobs tablosundan izlenir.
//
// Gizli değerler (supabase secrets): GEMINI_API_KEY; isteğe bağlı
// GEMINI_MODEL (varsayılan gemini-flash-latest), GEMINI_THINKING (düşünme
// seviyesi: low | medium | high, varsayılan medium) ve 1M token başına USD
// fiyatlar GEMINI_PRICE_INPUT (görüntü+metin, 0.5), GEMINI_PRICE_AUDIO (1.0),
// GEMINI_PRICE_OUTPUT (3.0).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { aiModel, refreshUsdTry, seasonAiEnabled } from "../_shared/ai_settings.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const DEFAULT_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-flash-latest";
// Her istekte Yapay Zekâ Yönetimi'ndeki seçimle (flash / pro) güncellenir.
let GEMINI_MODEL = DEFAULT_MODEL;
const GEMINI_THINKING = Deno.env.get("GEMINI_THINKING") ?? "medium";
const FLASH_INPUT = Number(Deno.env.get("GEMINI_PRICE_INPUT") ?? "0.5");
const FLASH_AUDIO = Number(Deno.env.get("GEMINI_PRICE_AUDIO") ?? "1.0");
const FLASH_OUTPUT = Number(Deno.env.get("GEMINI_PRICE_OUTPUT") ?? "3.0");
// Pro (1M token başına $): giriş 2, çıkış 12; ses girişi de 2.
const isPro = () => GEMINI_MODEL.includes("pro");
const priceInput = () => (isPro() ? 2.0 : FLASH_INPUT);
const priceAudio = () => (isPro() ? 2.0 : FLASH_AUDIO);
const priceOutput = () => (isPro() ? 12.0 : FLASH_OUTPUT);
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const YOUTUBE_API_KEY = Deno.env.get("YOUTUBE_API_KEY") ?? "";

/** YouTube canlı yayını bitti mi? (videos.list, 1 kota birimi)
 *  "live" / "upcoming": sürüyor ya da başlamadı; "ended": bitti ya da canlı
 *  yayın değil; "unknown": API yanıt vermedi (analiz denenir). */
async function youtubeLiveState(videoId: string): Promise<string> {
  if (!YOUTUBE_API_KEY) return "unknown";
  try {
    const res = await fetch(
      "https://www.googleapis.com/youtube/v3/videos?part=snippet,liveStreamingDetails" +
        `&id=${encodeURIComponent(videoId)}&key=${YOUTUBE_API_KEY}`,
    );
    if (!res.ok) return "unknown";
    const j = await res.json();
    const item = j?.items?.[0];
    if (!item) return "unknown";
    const lbc = String(item.snippet?.liveBroadcastContent ?? "none");
    if (lbc === "live" || lbc === "upcoming") return lbc;
    const details = item.liveStreamingDetails;
    if (details && details.actualStartTime && !details.actualEndTime) return "live";
    return "ended";
  } catch (_) {
    return "unknown";
  }
}

/** Canlı yayının gerçek başlama saati (ms) ve video süresi (sn); YouTube
 *  vermezse null. */
async function youtubeTiming(
  videoId: string,
): Promise<{ startMs: number | null; durationSec: number | null }> {
  const none = { startMs: null, durationSec: null };
  if (!YOUTUBE_API_KEY) return none;
  try {
    const res = await fetch(
      "https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails,contentDetails" +
        `&id=${encodeURIComponent(videoId)}&key=${YOUTUBE_API_KEY}`,
    );
    if (!res.ok) return none;
    const item = (await res.json())?.items?.[0];
    const t = item?.liveStreamingDetails?.actualStartTime;
    const ms = t ? Date.parse(t) : NaN;
    // ISO 8601 süre: PT1H32M10S
    const d = /PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/.exec(item?.contentDetails?.duration ?? "");
    const dur = d ? (+(d[1] ?? 0)) * 3600 + (+(d[2] ?? 0)) * 60 + (+(d[3] ?? 0)) : 0;
    return {
      startMs: Number.isFinite(ms) ? ms : null,
      durationSec: dur > 0 ? dur : null,
    };
  } catch (_) {
    return none;
  }
}

const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// Düşük çözünürlükte saniye başına yaklaşık token (Gemini belgeleri).
const VIDEO_TOKENS_PER_FRAME = 66;
const AUDIO_TOKENS_PER_SEC = 32;
// Çağrı başına tahmini çıktı (+ düşünme) token'ı.
const OUTPUT_TOKENS_GUESS = 4000;

// Gol penceresi: başlangıç biliniyorsa ±2 dk, bilinmiyorsa ±10 dk.
const NARROW = 120;
const WIDE = 600;
// Devre arası belirsizliği (başlangıç bilinmiyorsa 2. yarı penceresine eklenir).
const HALFTIME_SLACK = 900;
// Başlangıç tespitinde kare hızı (5 sn'de bir kare).
const DETECT_FPS = 0.2;
// Bulunamayan gol için ikinci tarama: ±5 dk.
const RETRY_WINDOW = 300;
// Skor tabelası okumada kare hızı (2 sn'de bir kare, 90 sn'lik aralık).
const CLOCK_FPS = 0.5;
// Tüm video taramasında kare hızı (varsayılan 2 sn'de bir kare; görüntü
// maliyeti yarıya iner, ses aynı kalır).
const FULL_FPS = Number(Deno.env.get("GEMINI_FULL_FPS") ?? "0.5");

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

/** YouTube linkinden 11 karakterlik video kimliği. */
function youtubeId(url: string): string | null {
  const u = url.trim();
  if (/^[\w-]{11}$/.test(u)) return u;
  try {
    const p = new URL(u.includes("://") ? u : `https://${u}`);
    const host = p.hostname.toLowerCase();
    let id: string | null = null;
    if (host.endsWith("youtu.be")) id = p.pathname.split("/")[1] ?? null;
    else if (host.includes("youtube.com") || host.includes("youtube-nocookie.com")) {
      id = p.searchParams.get("v");
      const seg = p.pathname.split("/").filter(Boolean);
      if (!id && seg.length >= 2 && ["embed", "shorts", "live", "v"].includes(seg[0])) {
        id = seg[1];
      }
    }
    return id && /^[\w-]{11}$/.test(id) ? id : null;
  } catch {
    return null;
  }
}

/** "1:02:03", "02:03", "123" → saniye. */
function toSec(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return Math.round(v);
  if (typeof v !== "string" || !v.trim()) return null;
  const parts = v.trim().split(":").map((x) => Number(x));
  if (parts.some((x) => !Number.isFinite(x))) return null;
  return Math.round(parts.reduce((acc, x) => acc * 60 + x, 0));
}

function fmt(sec: number): string {
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  return [h, m, s].map((x) => String(x).padStart(2, "0")).join(":");
}

type GoalEvent = {
  no: number;
  id: string;
  playerId: string | null;
  /** Dakika tutulmayan sezonda (halısaha) null. */
  minute: number | null;
  /** Uzatma dakikası (30+2' → minute 30, added 2). */
  added: number | null;
  teamId: string | null;
  teamName: string;
  player: string;
  ownGoal: boolean;
  penalty: boolean;
};

type Window = { start: number; end: number; goals: GoalEvent[] };

/** Esamedeki (yoksa kadrodaki) oyuncu. */
type RosterPlayer = { id: string; teamId: string; name: string; jersey: number | null };

type FoundGoal = {
  olay_no?: number | null;
  atan_oyuncu?: string | null;
  forma_no?: number | null;
  atan_takim?: string | null;
  mac_dakikasi?: string | number | null;
  gol_ani?: string | null;
  baslangic?: string | null;
  bitis?: string | null;
  aciklama?: string | null;
  guven?: string | null;
};

// --- Maliyet -----------------------------------------------------------------

/** Bir çağrının tahmini maliyeti (USD). */
function estimateCost(seconds: number, fps = 1): number {
  const video = seconds * fps * VIDEO_TOKENS_PER_FRAME;
  const audio = seconds * AUDIO_TOKENS_PER_SEC;
  return (video * priceInput() + audio * priceAudio() + OUTPUT_TOKENS_GUESS * priceOutput()) / 1e6;
}

type Usage = {
  text: number;
  video: number;
  audio: number;
  output: number;
  cost: number;
};

function usageOf(meta: Record<string, unknown> | undefined): Usage {
  const details = (meta?.promptTokensDetails ?? []) as { modality?: string; tokenCount?: number }[];
  const by = (m: string) =>
    details.filter((d) => d.modality === m).reduce((a, d) => a + (d.tokenCount ?? 0), 0);
  const text = by("TEXT") + by("IMAGE");
  const video = by("VIDEO");
  const audio = by("AUDIO");
  const output = Number(meta?.candidatesTokenCount ?? 0) + Number(meta?.thoughtsTokenCount ?? 0);
  const cost = ((text + video) * priceInput() + audio * priceAudio() + output * priceOutput()) / 1e6;
  return { text, video, audio, output, cost };
}

/** Bir analiz işinin harcamasını izler; sınırı aşacak çağrıyı engeller. */
class Budget {
  spent = 0;
  constructor(private matchId: string, private limit: number) {}

  ensure(estimate: number) {
    if (this.spent + estimate > this.limit) {
      throw new Error(
        `Maliyet sınırı: bu maç için ${this.limit.toFixed(2)} $ sınırına ulaşılacaktı, analiz durduruldu.`,
      );
    }
  }

  async record(purpose: string, u: Usage) {
    this.spent += u.cost;
    await admin.from("ai_usage_log").insert({
      match_id: this.matchId,
      model: GEMINI_MODEL,
      purpose,
      text_tokens: u.text,
      video_tokens: u.video,
      audio_tokens: u.audio,
      output_tokens: u.output,
      cost_usd: Number(u.cost.toFixed(5)),
    });
    await admin.from("match_highlight_jobs")
      .update({ cost_usd: Number(this.spent.toFixed(5)) })
      .eq("match_id", this.matchId);
  }
}

async function readLimits() {
  const { data } = await admin.from("app_private_settings")
    .select("key, value")
    .in("key", ["ai_clip_max_usd_per_match", "ai_clip_monthly_usd"]);
  const get = (k: string, d: number) => {
    const v = Number((data ?? []).find((r) => r.key === k)?.value);
    return Number.isFinite(v) && v > 0 ? v : d;
  };
  return {
    perMatch: get("ai_clip_max_usd_per_match", 0.5),
    monthly: get("ai_clip_monthly_usd", 5),
  };
}

async function spentThisMonth(): Promise<number> {
  const now = new Date();
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const { data } = await admin.from("ai_usage_log")
    .select("cost_usd").gte("created_at", monthStart.toISOString());
  return (data ?? []).reduce((a, r) => a + Number(r.cost_usd ?? 0), 0);
}

// --- Gemini ------------------------------------------------------------------

async function askGemini(opts: {
  videoId: string;
  prompt: string;
  schema: Record<string, unknown>;
  start?: number;
  end?: number;
  fps?: number;
}): Promise<{ data: Record<string, unknown>; usage: Usage }> {
  const videoPart: Record<string, unknown> = {
    fileData: { fileUri: `https://www.youtube.com/watch?v=${opts.videoId}` },
  };
  const meta: Record<string, unknown> = {};
  if (opts.start != null) meta.startOffset = `${opts.start}s`;
  if (opts.end != null) meta.endOffset = `${opts.end}s`;
  if (opts.fps != null) meta.fps = opts.fps;
  if (Object.keys(meta).length) videoPart.videoMetadata = meta;

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [videoPart, { text: opts.prompt }] }],
        generationConfig: {
          temperature: 0.2,
          mediaResolution: "MEDIA_RESOLUTION_LOW",
          responseMimeType: "application/json",
          responseSchema: opts.schema,
          thinkingConfig: { thinkingLevel: GEMINI_THINKING },
        },
      }),
    },
  );
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = body?.error?.message ?? `HTTP ${res.status}`;
    throw new Error(`Gemini: ${msg}`);
  }
  const text: string = body?.candidates?.[0]?.content?.parts
    ?.map((p: { text?: string }) => p.text ?? "")
    .join("") ?? "";
  return { data: JSON.parse(text || "{}"), usage: usageOf(body?.usageMetadata) };
}

// --- Başlangıç tespiti ---------------------------------------------------------

const KICKOFF_SCHEMA = {
  type: "OBJECT",
  properties: {
    an: { type: "STRING", nullable: true },
    guven: { type: "STRING", enum: ["yuksek", "orta", "dusuk"] },
  },
  required: ["guven"],
};

async function detectStart(
  budget: Budget,
  videoId: string,
  which: "kickoff" | "second_half",
  start: number,
  end: number,
): Promise<number | null> {
  budget.ensure(estimateCost(end - start, DETECT_FPS));
  const what = which === "kickoff"
    ? "maçın BAŞLAMA VURUŞUNUN (ilk yarı) yapıldığı anı"
    : "devre arasından sonra İKİNCİ YARININ başlama vuruşunun yapıldığı anı";
  const prompt = [
    "Bu bir amatör futbol maçının videosudur.",
    `Sana videonun ${fmt(start)} – ${fmt(end)} aralığı verildi.`,
    `Bu aralıkta ${what} bul: oyuncular sahaya dizilmiş, top orta noktada,`,
    "hakem düdüğüyle oyun başlıyor. Spiker veya skor tabelası varsa onları da kullan.",
    "Zamanı VİDEONUN EN BAŞINDAN İTİBAREN (mutlak) SS:DD:ss olarak 'an' alanına yaz.",
    "Bulamazsan 'an' boş, guven 'dusuk' olsun. Uydurma.",
  ].join("\n");
  const { data, usage } = await askGemini({
    videoId,
    prompt,
    schema: KICKOFF_SCHEMA,
    start,
    end,
    fps: DETECT_FPS,
  });
  await budget.record(which, usage);
  if (data.guven === "dusuk") return null;
  let sec = toSec(data.an);
  if (sec == null) return null;
  if (sec < start) sec += start; // aralığa göre verdiyse mutlağa çevir
  return sec >= start - 30 && sec <= end + 30 ? sec : null;
}

const CLOCK_SCHEMA = {
  type: "OBJECT",
  properties: {
    video_ani: { type: "STRING", nullable: true },
    tabela_suresi: { type: "STRING", nullable: true },
  },
};

/** Skor tabelasındaki maç sayacını okur: videodaki an ve o anda tabelada
 *  yazan süre (sn). Tabela/sayaç yoksa null. Kısa aralık, ucuz. */
async function readClock(
  budget: Budget,
  videoId: string,
  start: number,
  end: number,
): Promise<{ videoSec: number; clockSec: number } | null> {
  budget.ensure(estimateCost(end - start, CLOCK_FPS));
  const prompt = [
    "Bu bir amatör futbol maçı yayınıdır.",
    `Sana videonun ${fmt(start)} – ${fmt(end)} aralığı verildi.`,
    "Ekranda skor tabelası ve üzerinde işleyen MAÇ SÜRESİ (sayaç, ör. 12:40)",
    "görünüyorsa sayacın net okunduğu tek bir an seç.",
    "video_ani: o anın VİDEONUN EN BAŞINDAN İTİBAREN zamanı (SS:DD:ss).",
    "tabela_suresi: o anda tabelada yazan maç süresi (DD:ss).",
    "Tabela ya da sayaç yoksa veya okunamıyorsa ikisini de boş bırak. Uydurma.",
  ].join("\n");
  try {
    const { data, usage } = await askGemini({
      videoId,
      prompt,
      schema: CLOCK_SCHEMA,
      start,
      end,
      fps: CLOCK_FPS,
    });
    await budget.record("clock", usage);
    let v = toSec(data.video_ani);
    const c = toSec(data.tabela_suresi);
    if (v == null || c == null) return null;
    if (v < start) v += start;
    if (v < start - 30 || v > end + 30) return null;
    return { videoSec: v, clockSec: c };
  } catch (e) {
    console.warn("readClock", (e as Error).message);
    return null;
  }
}

/** Devre başlangıçlarını videoda bulur, en ucuzdan pahalıya:
 *  1) uygulamadaki düdük saati − YouTube yayın başlangıcı (ücretsiz),
 *  2) skor tabelasındaki sayaçla doğrulama/düzeltme (kısa ve ucuz),
 *  3) son çare: başlama vuruşunu videoda arama.
 *  Yayın maç başladıktan sonra açıldıysa başlangıç negatif çıkar. */
async function resolveStarts(
  budget: Budget,
  o: {
    videoId: string;
    period: number;
    needSecond: boolean;
    kickoffAt: string | null;
    secondHalfAt: string | null;
  },
): Promise<{ kickoff: number | null; secondHalf: number | null; disagree: boolean; source: string }> {
  const yt = await youtubeTiming(o.videoId);
  const periodSec = o.period * 60;
  // Düdüklere maç sırasında basıldıysa saat kullanılır. Sonradan girilen
  // maçta (iki düdük art arda) saat yayının sonunu gösterir: kullanılmaz.
  const k = o.kickoffAt ? Date.parse(o.kickoffAt) : NaN;
  const h = o.secondHalfAt ? Date.parse(o.secondHalfAt) : NaN;
  const liveEntered = Number.isFinite(k) &&
    (!Number.isFinite(h) || h - k >= (periodSec - 300) * 1000);
  const offset = (iso: string | null) => {
    if (!liveEntered || yt.startMs == null || !iso) return null;
    const ms = Date.parse(iso);
    if (!Number.isFinite(ms)) return null;
    const sec = Math.round((ms - yt.startMs) / 1000);
    // Yayından 1 saatten fazla önce ya da videonun bitimine yakın: güvenilmez.
    const maxSec = yt.durationSec != null ? yt.durationSec - 600 : 4 * 3600;
    return sec > -3600 && sec < maxSec ? sec : null;
  };
  let disagree = false;
  const sources: string[] = [];

  // 1. yarı
  const est1 = offset(o.kickoffAt);
  if (est1 != null) sources.push("saat");
  let kickoff = est1;
  const probe1 = Math.max(0, (est1 ?? 0) + 240);
  const clk1 = await readClock(budget, o.videoId, probe1, probe1 + 90);
  if (clk1 && clk1.clockSec <= periodSec + 900) {
    const cand = clk1.videoSec - clk1.clockSec;
    if (est1 != null && Math.abs(cand - est1) > 180) disagree = true;
    kickoff = cand; // tabela, düğmeye basılan andan daha güvenilir
    sources.push("tabela");
  }
  if (kickoff == null) {
    kickoff = await detectStart(budget, o.videoId, "kickoff", 0, 1200);
    if (kickoff != null) sources.push("düdük");
  }

  // 2. yarı
  let secondHalf: number | null = null;
  if (o.needSecond) {
    const est2 = offset(o.secondHalfAt);
    secondHalf = est2;
    const guess = est2 ?? (kickoff != null ? kickoff + periodSec + 600 : null);
    if (guess != null) {
      const probe2 = Math.max(0, guess + 240);
      const clk2 = await readClock(budget, o.videoId, probe2, probe2 + 90);
      if (clk2) {
        // Sayaç ikinci yarıda devam ediyorsa (35:00) ya da sıfırlandıysa (05:00).
        const intoHalf = clk2.clockSec >= periodSec - 60
          ? clk2.clockSec - periodSec
          : clk2.clockSec;
        const cand = clk2.videoSec - intoHalf;
        if (kickoff == null || cand > kickoff + periodSec - 120) {
          if (est2 != null && Math.abs(cand - est2) > 180) disagree = true;
          secondHalf = cand;
        }
      }
    }
    if (secondHalf == null && kickoff != null) {
      const from = kickoff + periodSec;
      secondHalf = await detectStart(budget, o.videoId, "second_half", from, from + 1500);
    }
  }
  return { kickoff, secondHalf, disagree, source: sources.join("+") };
}

// --- Gol taraması -------------------------------------------------------------

const GOALS_SCHEMA = {
  type: "OBJECT",
  properties: {
    goller: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          olay_no: { type: "INTEGER", nullable: true },
          atan_takim: { type: "STRING", nullable: true },
          mac_dakikasi: { type: "STRING", nullable: true },
          gol_ani: { type: "STRING" },
          baslangic: { type: "STRING", nullable: true },
          bitis: { type: "STRING", nullable: true },
          aciklama: { type: "STRING", nullable: true },
          atan_oyuncu: { type: "STRING", nullable: true },
          forma_no: { type: "INTEGER", nullable: true },
          guven: { type: "STRING", enum: ["yuksek", "orta", "dusuk"] },
        },
        required: ["gol_ani", "guven"],
      },
    },
    // Yalnız tüm video taramasında: maç dakikasını hesaplamak için.
    mac_baslangic: { type: "STRING", nullable: true },
    ikinci_yari_baslangic: { type: "STRING", nullable: true },
  },
  required: ["goller"],
};

/** Türkçe harfleri sadeleştirip küçültür (ad eşleştirme için). */
function norm(s: string) {
  return s.toLocaleLowerCase("tr")
    .replace(/ı/g, "i").replace(/ş/g, "s").replace(/ğ/g, "g")
    .replace(/ü/g, "u").replace(/ö/g, "o").replace(/ç/g, "c")
    .replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ").trim();
}

/**
 * YZ'nin verdiği ad / forma numarasını esameyle eşleştirir. Önce takım +
 * forma no, sonra ad: tam ad, soyad ya da (tek eşleşmeyse) ad.
 */
function matchPlayer(
  roster: RosterPlayer[],
  teamId: string | null,
  name: string | null | undefined,
  jersey: number | null | undefined,
): string | null {
  const pool = teamId ? roster.filter((p) => p.teamId === teamId) : roster;
  if (jersey != null && teamId) {
    const byNo = pool.filter((p) => p.jersey === jersey);
    if (byNo.length === 1) return byNo[0].id;
  }
  const n = norm(name ?? "");
  if (!n) return null;
  const words = n.split(" ");
  const full = pool.filter((p) => norm(p.name) === n);
  if (full.length === 1) return full[0].id;
  const last = words[words.length - 1];
  const bySurname = pool.filter((p) => {
    const w = norm(p.name).split(" ");
    return w[w.length - 1] === last;
  });
  if (bySurname.length === 1) return bySurname[0].id;
  if (words.length === 1) {
    const byFirst = pool.filter((p) => norm(p.name).split(" ")[0] === words[0]);
    if (byFirst.length === 1) return byFirst[0].id;
  }
  return null;
}

function goalsPrompt(
  home: string,
  away: string,
  window: Window | null,
  goals: GoalEvent[],
  roster: { home: RosterPlayer[]; away: RosterPlayer[] },
) {
  const lines = [
    "Bu bir amatör futbol maçının videosudur. Görevin maçtaki GOLLERİ bulmak.",
    "",
    `Ev sahibi: ${home}`,
    `Deplasman: ${away}`,
    "",
    "GOLÜ NASIL TESPİT EDECEKSİN",
    "1. Ekranda skor tabelası varsa, skorun değiştiği an bir goldür; golün",
    "   atıldığı asıl ana geri git (tabela genelde birkaç saniye sonra güncellenir).",
    "2. Golü görüntüden doğrula: topun ağlara gitmesi, sevinç, oyunun orta",
    "   sahadan yeniden başlaması. Spiker varsa anlatımı da kullan.",
    "3. Görmediğin bir golü uydurma; emin değilsen guven 'dusuk' olsun.",
    "",
  ];
  if (window) {
    lines.push(
      `Sana videonun yalnızca ${fmt(window.start)} – ${fmt(window.end)} aralığı verildi.`,
      "TÜM ZAMANLARI VİDEONUN EN BAŞINDAN İTİBAREN (mutlak) yaz, bu aralığın",
      "başından itibaren değil.",
      "",
    );
  } else {
    lines.push(
      "Tüm videoyu tara; zamanları videonun başından itibaren yaz.",
      "Ayrıca maçın başlama vuruşunun (mac_baslangic) ve 2. yarının başlama",
      "vuruşunun (ikinci_yari_baslangic) videodaki anını yaz (SS:DD:ss).",
      "",
    );
  }
  const list = (ps: RosterPlayer[]) =>
    ps.map((p) => (p.jersey != null ? `${p.jersey} ${p.name}` : p.name)).join(", ");
  if (roster.home.length || roster.away.length) {
    lines.push(
      "Kadrolar (forma no + ad):",
      `- ${home}: ${list(roster.home) || "-"}`,
      `- ${away}: ${list(roster.away) || "-"}`,
      "",
    );
  }
  if (goals.length) {
    lines.push(
      window
        ? "Maç raporuna göre bu aralıkta şu goller var (dakika maç dakikasıdır, video zamanı değil):"
        : goals.some((g) => g.minute == null)
        ? "Maç raporundaki goller (dakika tutulmadı; giriliş sırasıyla):"
        : "Maç raporundaki goller (dakika maç dakikasıdır, video zamanı değil):",
    );
    for (const g of goals) {
      const extra = g.ownGoal ? " (kendi kalesine)" : g.penalty ? " (penaltı)" : "";
      lines.push(
        `- olay_no ${g.no}: ${g.minute != null ? `${g.minute}${g.added ? `+${g.added}` : ""}' ` : ""}${g.teamName}${g.player ? ` – ${g.player}` : ""}${extra}`,
      );
    }
    lines.push(
      "Bu golleri videoda bul ve her biri için olay_no'yu yaz. Eşleştirmeyi",
      "zamana ve takıma göre yap: spikerin söylediği oyuncu rapordakinden",
      "farklı olsa da o gol aynı goldür, olay_no'yu yine yaz (raporu esas al).",
      "Raporda olmayan bir gol görürsen olay_no'yu boş bırakarak ekle.",
      "",
    );
  }
  lines.push(
    "Her gol için:",
    "- gol_ani: topun çizgiyi geçtiği an (SS:DD:ss)",
    "- baslangic: golle sonuçlanan atağın başı (~10 sn önce)",
    "- bitis: sevinç başladıktan ~5 sn sonra",
    "- atan_takim: golü atan takımın adı (yukarıdaki adlardan biri)",
    "- mac_dakikasi: tabelada okunuyorsa maç süresi, yoksa boş",
    "- aciklama: kısa Türkçe açıklama; olay_no verdiysen oyuncu adı yazma",
    "  (golü atan maç raporundan gösterilir)",
    "- atan_oyuncu: golü atanın adı, yalnızca spiker söylüyorsa ya da",
    "  formasından kesin okunuyorsa (kadrodaki yazılışla); yoksa boş",
    "- forma_no: golü atanın forma numarası, kesin okunuyorsa; yoksa boş",
    "- guven: yuksek | orta | dusuk",
  );
  return lines.join("\n");
}

/** Gol dakikalarından taranacak video aralıkları (çakışanlar birleşir). */
function buildWindows(
  goals: GoalEvent[],
  period: number,
  kickoff: number | null,
  secondHalf: number | null,
  narrow = NARROW,
): Window[] {
  const raw: Window[] = goals.map((g) => {
    const minute = g.minute ?? 0;
    // Uzatma (30+2'): devre içinde süreye eklenir, devre değişmez.
    const extra = (g.added ?? 0) * 60;
    const firstHalf = minute <= period;
    let center: number;
    let before = narrow;
    let after = narrow;
    if (!firstHalf && secondHalf != null) {
      center = secondHalf + (minute - period) * 60 + extra;
    } else {
      center = (kickoff ?? 0) + minute * 60 + extra;
      if (kickoff == null || !firstHalf) {
        // Başlangıç bilinmiyor: geniş pencere; 2. yarıda devre arası da eklenir.
        before = WIDE;
        after = firstHalf ? WIDE : WIDE + HALFTIME_SLACK;
      }
    }
    return { start: Math.max(0, center - before), end: center + after, goals: [g] };
  });
  raw.sort((a, b) => a.start - b.start);
  const merged: Window[] = [];
  for (const w of raw) {
    const last = merged[merged.length - 1];
    if (last && w.start <= last.end) {
      last.end = Math.max(last.end, w.end);
      last.goals.push(...w.goals);
    } else {
      merged.push({ ...w, goals: [...w.goals] });
    }
  }
  return merged;
}

const CONFIDENCE: Record<string, string> = { yuksek: "high", orta: "medium", dusuk: "low" };

type RunOpts = {
  matchId: string;
  videoId: string;
  home: { id: string; name: string };
  away: { id: string; name: string };
  goals: GoalEvent[];
  period: number;
  kickoff: number | null;
  secondHalf: number | null;
  /** Uygulamada başlama / 2. yarı düdüğüne basılan an (ISO). */
  kickoffAt: string | null;
  secondHalfAt: string | null;
  limit: number;
  roster: RosterPlayer[];
  /** Sezon tercihi: kesitler doğrudan yayına girer. */
  autoPublish: boolean;
};

/** Tüm gollerin dakikası girilmiş mi? (pencereli tarama yapılabilir) */
function isTimed(goals: GoalEvent[]) {
  return goals.length > 0 && goals.every((g) => g.minute != null);
}

/** Videonun yaklaşık süresi (sn): başlangıç + iki devre + devre arası. */
function approxVideoLength(period: number, kickoff: number | null) {
  return (kickoff ?? 0) + (2 * period) * 60 + HALFTIME_SLACK;
}

async function run(opts: RunOpts) {
  const { matchId, videoId, home, away, goals, period } = opts;
  // Tüm gollerin dakikası varsa pencereli tarama; yoksa (halısaha) tüm video.
  const timed = isTimed(goals);
  const budget = new Budget(matchId, opts.limit);
  let { kickoff, secondHalf } = opts;
  try {
    // 1) Başlangıçlar elle verilmediyse sistem bulur (bkz. resolveStarts).
    let disagree = false;
    if (timed) {
      const needSecond = goals.some((g) => (g.minute ?? 0) > period);
      if (kickoff == null || (needSecond && secondHalf == null)) {
        const r = await resolveStarts(budget, {
          videoId,
          period,
          needSecond: needSecond && secondHalf == null,
          kickoffAt: opts.kickoffAt,
          secondHalfAt: opts.secondHalfAt,
        });
        kickoff ??= r.kickoff;
        secondHalf ??= r.secondHalf;
        disagree = r.disagree;
        console.log("starts", matchId, r.source, kickoff, secondHalf);
      }
      await admin.from("match_highlight_jobs")
        .update({ kickoff_sec: kickoff, second_half_sec: secondHalf })
        .eq("match_id", matchId);
    }

    // 2) Taranacak aralıklar; 3) tavan: büyük kısmı kaplıyorsa tüm video.
    let windows: (Window | null)[] = timed
      ? buildWindows(goals, period, kickoff, secondHalf)
      : [null];
    const covered = windows.reduce((a, w) => a + (w ? w.end - w.start : 0), 0);
    const total = approxVideoLength(period, kickoff);
    if (timed && covered > total * 0.7) windows = [null];

    const plannedCost = windows.reduce(
      (a, w) => a + (w ? estimateCost(w.end - w.start) : estimateCost(total, FULL_FPS)),
      0,
    );
    budget.ensure(plannedCost);

    const scanWindows = (ws: (Window | null)[]) => Promise.all(
      ws.map(async (w) => {
        const { data, usage } = await askGemini({
          videoId,
          prompt: goalsPrompt(home.name, away.name, w, w ? w.goals : goals, {
            home: opts.roster.filter((p) => p.teamId === home.id),
            away: opts.roster.filter((p) => p.teamId === away.id),
          }),
          schema: GOALS_SCHEMA,
          start: w?.start,
          end: w?.end,
          fps: w ? undefined : FULL_FPS,
        });
        await budget.record(w ? "goals" : "full", usage);
        const found = Array.isArray(data.goller) ? (data.goller as FoundGoal[]) : [];
        // Tüm video taramasında başlangıçlar bu yanıttan gelir.
        if (!w) {
          kickoff ??= toSec(data.mac_baslangic as string | null);
          secondHalf ??= toSec(data.ikinci_yari_baslangic as string | null);
        }
        return { w, found };
      }),
    );

    const results = await scanWindows(windows);

    const rows: Record<string, unknown>[] = [];
    const usedEvents = new Set<string>();
    const seenSec: number[] = [];
    const collect = (res: { w: Window | null; found: FoundGoal[] }[]) => {
    for (const { w, found } of res) {
      for (const f of found) {
        let goalSec = toSec(f.gol_ani);
        if (goalSec == null) continue;
        // Model zamanı aralığın başından verdiyse mutlağa çevir.
        if (w && goalSec < w.start) goalSec += w.start;
        if (w && (goalSec < w.start - 30 || goalSec > w.end + 30)) continue;
        // Aynı gol iki pencereden gelmesin.
        if (seenSec.some((s) => Math.abs(s - goalSec!) < 20)) continue;
        seenSec.push(goalSec);

        let start = toSec(f.baslangic);
        let end = toSec(f.bitis);
        if (w && start != null && start < w.start) start += w.start;
        if (w && end != null && end < w.start) end += w.start;
        if (start == null || start > goalSec - 3 || start < goalSec - 30) start = goalSec - 12;
        if (end == null || end < goalSec + 3 || end > goalSec + 20) end = goalSec + 8;
        start = Math.max(0, start);

        const teamName = (f.atan_takim ?? "").toLocaleLowerCase("tr");
        const sideOf = (g: GoalEvent) =>
          g.ownGoal ? (g.teamId === home.id ? away.id : home.id) : g.teamId;
        const foundTeam = teamName && home.name.toLocaleLowerCase("tr").includes(teamName)
          ? home.id
          : teamName && away.name.toLocaleLowerCase("tr").includes(teamName)
          ? away.id
          : null;
        let ev = f.olay_no != null
          ? goals.find((g) => g.no === f.olay_no && !usedEvents.has(g.id))
          : undefined;
        // YZ olay_no vermediyse (ör. spiker başka oyuncu adı söyledi) bu
        // aralıktaki kullanılmamış gol olayı eşleşir: önce aynı takım, tek
        // adaysa takım bilinmese de. Dakika ve oyuncu maç raporundan gelir.
        if (!ev && w) {
          const free = w.goals.filter((g) => !usedEvents.has(g.id));
          const same = foundTeam ? free.filter((g) => sideOf(g) === foundTeam) : [];
          ev = same[0] ?? (free.length === 1 && !foundTeam ? free[0] : undefined);
        }
        if (ev) usedEvents.add(ev.id);

        const teamId = ev ? sideOf(ev) : foundTeam;

        // Dakika: maç detayından; yoksa tabeladan; o da yoksa videodaki
        // başlangıç anlarından hesaplanır.
        let minuteRaw = ev?.minute ?? parseInt(String(f.mac_dakikasi ?? ""), 10);
        if (!Number.isFinite(minuteRaw) && kickoff != null && goalSec >= kickoff) {
          minuteRaw = secondHalf != null && goalSec >= secondHalf
            ? period + Math.floor((goalSec - secondHalf) / 60) + 1
            : Math.floor((goalSec - kickoff) / 60) + 1;
        }
        const playerId = ev?.playerId ??
          matchPlayer(opts.roster, teamId, f.atan_oyuncu, f.forma_no);
        rows.push({
          match_id: matchId,
          kind: "goal",
          match_event_id: ev?.id ?? null,
          team_id: teamId,
          player_id: playerId,
          minute: Number.isFinite(minuteRaw) ? minuteRaw : null,
          added_minute: ev?.added ?? null,
          video_id: videoId,
          start_sec: start,
          end_sec: end,
          description: (f.aciklama ?? "").trim() || null,
          confidence: CONFIDENCE[f.guven ?? ""] ?? null,
          status: opts.autoPublish ? "approved" : "pending",
          source: "ai",
        });
      }
    }
    };
    collect(results);

    // Görüntüsü bulunamayan goller: aralık bir kez genişletilip yeniden
    // taranır (bütçe yetmezse atlanır). Hâlâ yoksa hata verilmez; o gol
    // "yayında görüntü yok" sayılır, diğer kesitler yayınlanır.
    let missing = timed ? goals.filter((g) => !usedEvents.has(g.id)) : [];
    if (missing.length && windows[0] != null) {
      const retry = buildWindows(missing, period, kickoff, secondHalf, RETRY_WINDOW);
      try {
        budget.ensure(retry.reduce((t, w) => t + estimateCost(w.end - w.start), 0));
        collect(await scanWindows(retry));
      } catch (e) {
        console.warn("retry skipped", matchId, (e as Error).message);
      }
      missing = goals.filter((g) => !usedEvents.has(g.id));
    }
    // Belirsizlikte yetkiliye haber: saat ile tabela tutmadı ya da gollerin
    // yarısından azı bulundu.
    const foundGoals = goals.length - missing.length;
    const needsReview = timed && (disagree || foundGoals * 2 < goals.length);

    // Yeniden çalıştırmada sorumlunun dokunmadığı eski YZ kesitleri silinir;
    // onaylanan, düzeltilen ya da kaldırılanlar (reviewed_by dolu) kalır.
    await admin.from("match_highlights").delete()
      .eq("match_id", matchId).eq("source", "ai").is("reviewed_by", null);
    if (rows.length) {
      const { error } = await admin.from("match_highlights").insert(rows);
      if (error) throw new Error(error.message);
    }
    await admin.from("match_highlight_jobs").update({
      status: "done",
      kickoff_sec: kickoff,
      second_half_sec: secondHalf,
      mode: windows[0] == null ? "full" : "events",
      found: rows.length,
      missing: missing.length,
      needs_review: needsReview,
      cost_usd: Number(budget.spent.toFixed(5)),
      finished_at: new Date().toISOString(),
    }).eq("match_id", matchId);
    if (needsReview) {
      await admin.rpc("highlights_review_notify", {
        p_match_id: matchId,
        p_text: disagree
          ? "Yayının başlangıcı net bulunamadı; gol kesitlerini kontrol edin."
          : `${goals.length} golden ${foundGoals} tanesi yayında bulundu; kesitleri kontrol edin.`,
      });
    }
  } catch (e) {
    console.error("video-highlights", matchId, (e as Error).message);
    await admin.from("match_highlight_jobs").update({
      status: "error",
      error: (e as Error).message.slice(0, 500),
      cost_usd: Number(budget.spent.toFixed(5)),
      finished_at: new Date().toISOString(),
    }).eq("match_id", matchId);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST bekleniyor" }, 405);
  if (!GEMINI_API_KEY) return json({ error: "GEMINI_API_KEY ayarlı değil." }, 500);

  const auth = req.headers.get("Authorization") ?? "";
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
  });
  const body = await req.json().catch(() => ({}));
  const matchId = String(body?.match_id ?? "").trim();
  if (!matchId) return json({ error: "match_id eksik." }, 400);
  const kickoff = toSec(body?.kickoff_sec);
  const secondHalf = toSec(body?.second_half_sec);

  // Maç bitince veritabanı (highlights_auto_tick) gizli anahtarla çağırır.
  const syncGiven = req.headers.get("x-sync-secret") ?? "";
  let auto = false;
  if (syncGiven) {
    const { data: row } = await admin.from("app_private_settings")
      .select("value").eq("key", "highlights_sync_secret").maybeSingle();
    if (!row?.value || row.value !== syncGiven) {
      return json({ error: "Geçersiz anahtar." }, 401);
    }
    auto = true;
  }
  let userId: string | null = null;
  if (!auto) {
    const { data: userData } = await userClient.auth.getUser();
    if (!userData?.user) return json({ error: "Giriş gerekli." }, 401);
    userId = userData.user.id;
    const { data: allowed } = await userClient.rpc("owns_match", { p_match_id: matchId });
    if (allowed !== true) return json({ error: "Bu maç için yetkiniz yok." }, 403);
  }

  // Aynı maçta süren bir iş varsa (10 dk'dan yeni) yenisi başlatılmaz.
  const { data: job } = await admin.from("match_highlight_jobs")
    .select("status, started_at").eq("match_id", matchId).maybeSingle();
  if (
    job?.status === "running" &&
    Date.now() - new Date(job.started_at).getTime() < 10 * 60 * 1000
  ) {
    return json({ error: "Bu maç için analiz zaten sürüyor." }, 409);
  }

  const { data: m } = await admin.from("matches")
    .select("id, season_id, home_team_id, away_team_id, kickoff_at, second_half_at")
    .eq("id", matchId).maybeSingle();
  if (!m) return json({ error: "Maç bulunamadı." }, 404);
  if (!(await seasonAiEnabled(admin, m.season_id, "clips"))) {
    return json({ error: "Bu sezonda gol videosu yakalama kapalı." }, 403);
  }
  const { data: pub } = await admin.from("seasons")
    .select("ai_clips_auto_publish").eq("id", m.season_id).maybeSingle();
  const autoPublish = pub?.ai_clips_auto_publish !== false;
  GEMINI_MODEL = await aiModel(admin, "clips", DEFAULT_MODEL);
  await refreshUsdTry(admin);

  const { data: links } = await admin.from("match_media")
    .select("url, created_at").eq("match_id", matchId).eq("media_type", "Maç Yayın Linki")
    .order("created_at", { ascending: false });
  const videoId = (links ?? []).map((l) => youtubeId(l.url ?? "")).find((x) => x) ?? null;
  if (!videoId) return json({ error: "Maçın YouTube yayın linki yok." }, 400);

  // Elle başlatmada da yayın sürüyorsa analiz başlamaz (video henüz tamam
  // değil, deneme boşa gider).
  if (!auto && (await youtubeLiveState(videoId)) === "live") {
    return json({
      error: "YouTube yayını hâlâ sürüyor. Yayın kapandıktan sonra tekrar deneyin.",
    }, 409);
  }

  // Otomatik: YouTube yayını hâlâ sürüyorsa beklenir; veritabanı dakikada bir
  // yeniden sorar. Bittiyse deneme sayılır ve analiz başlar.
  if (auto) {
    const state = await youtubeLiveState(videoId);
    if (state === "live" || state === "upcoming") {
      return json({ waiting: state }, 202);
    }
    const { data: att } = await admin.from("highlights_auto_attempts")
      .select("tries").eq("match_id", matchId).maybeSingle();
    await admin.from("highlights_auto_attempts").upsert({
      match_id: matchId,
      tries: (att?.tries ?? 0) + 1,
      called_at: new Date().toISOString(),
    });
  }

  const [{ data: teams }, { data: season }, { data: events, error: eventsError }] = await Promise.all([
    admin.from("teams").select("id, name").in("id", [m.home_team_id, m.away_team_id]),
    admin.from("seasons").select("match_period_duration").eq("id", m.season_id).maybeSingle(),
    admin.from("match_events")
      // match_events'te oyuncu adı sütunu yok; ad players'tan gelir. (Eski
      // sorgu olmayan sütunu istediği için hata dönüyor, maç dakikasız
      // sayılıp otomatik taranmıyordu.)
      .select("id, minute, added_minute, team_id, player_id, is_own_goal, is_penalty, " +
        "player:players!match_events_player_id_fkey(name, surname)")
      .eq("match_id", matchId).eq("event_type", "goal")
      .order("minute").order("added_minute", { nullsFirst: true }).order("created_at"),
  ]);
  // Goller okunamazsa maç dakikasız sanılıp tüm video taranmasın.
  if (eventsError) {
    return json({ error: `Goller okunamadı: ${eventsError.message}` }, 500);
  }
  const nameOf = (id: string) => (teams ?? []).find((t) => t.id === id)?.name ?? "";
  const home = { id: m.home_team_id, name: nameOf(m.home_team_id) || "Ev sahibi" };
  const away = { id: m.away_team_id, name: nameOf(m.away_team_id) || "Deplasman" };
  const period = Number(season?.match_period_duration) > 0
    ? Number(season!.match_period_duration)
    : 45;

  const goals: GoalEvent[] = (events ?? []).map((e, i) => ({
    no: i + 1,
    id: e.id,
    playerId: e.player_id ?? null,
    minute: e.minute == null ? null : Number(e.minute) || 0,
    added: Number((e as any).added_minute) > 0 ? Number((e as any).added_minute) : null,
    teamId: e.team_id,
    teamName: e.team_id === home.id ? home.name : e.team_id === away.id ? away.name : "",
    player: `${(e as any).player?.name ?? ""} ${(e as any).player?.surname ?? ""}`.trim(),
    ownGoal: !!e.is_own_goal,
    penalty: !!e.is_penalty,
  }));

  // Esame (yoksa sezon kadrosu): YZ'ye ad listesi + eşleştirme için.
  const rosterRows = (await admin.from("match_rosters")
    .select("player_id, team_id, jersey_number, players(name, surname)")
    .eq("match_id", matchId)).data ?? [];
  const squadRows = rosterRows.length ? [] : (await admin.from("season_team_players")
    .select("player_id, team_id, jersey_number, players(name, surname)")
    .eq("season_id", m.season_id)
    .in("team_id", [m.home_team_id, m.away_team_id])).data ?? [];
  // deno-lint-ignore no-explicit-any
  const roster: RosterPlayer[] = [...rosterRows, ...squadRows].map((r: any) => ({
    id: r.player_id,
    teamId: r.team_id,
    name: `${r.players?.name ?? ""} ${r.players?.surname ?? ""}`.trim(),
    jersey: r.jersey_number ?? null,
  })).filter((p) => p.id && p.name);

  // Sınırlar: en kötü durum tahmini (başlangıç bulunamazsa geniş pencereler
  // ya da tüm video) maç başı veya aylık sınırı aşıyorsa Gemini'ye gidilmez.
  const timed = isTimed(goals);
  // Dakikasız maçta tüm video taranır (pahalı): yalnız admin başlatabilir.
  if (!timed) {
    if (auto) return json({ error: "Dakikasız maç otomatik taranmaz." }, 400);
    const { data: isAdmin } = await userClient.rpc("is_admin");
    if (isAdmin !== true) {
      return json({ error: "Dakikası girilmemiş maçta YZ analizini yalnız admin başlatabilir." }, 403);
    }
  }
  const limits = await readLimits();
  const total = approxVideoLength(period, kickoff);
  const detectCost = timed
    ? (kickoff == null ? estimateCost(1200, DETECT_FPS) : 0) +
      (secondHalf == null ? estimateCost(1500, DETECT_FPS) : 0)
    : 0;
  const worstWindows = timed ? buildWindows(goals, period, kickoff, secondHalf) : [];
  const worstScan = timed
    ? Math.min(
      worstWindows.reduce((a, w) => a + estimateCost(w.end - w.start), 0),
      estimateCost(total),
    )
    : estimateCost(total, FULL_FPS);
  const worst = detectCost + worstScan;
  if (worst > limits.perMatch) {
    return json({
      error: `Tahmini maliyet (${worst.toFixed(2)} $) maç başı sınırı ` +
        `(${limits.perMatch.toFixed(2)} $) aşıyor. Videoda maçın ve 2. yarının ` +
        "başladığı anı girerek taranan süreyi kısaltın.",
    }, 400);
  }
  const spent = await spentThisMonth();
  if (spent + worst > limits.monthly) {
    return json({
      error: `Aylık YZ bütçesi doldu (${spent.toFixed(2)} / ${limits.monthly.toFixed(2)} $).`,
    }, 400);
  }

  await admin.from("match_highlight_jobs").upsert({
    match_id: matchId,
    status: "running",
    video_id: videoId,
    mode: timed ? "events" : "full",
    model: GEMINI_MODEL,
    found: null,
    error: null,
    cost_usd: 0,
    kickoff_sec: kickoff,
    second_half_sec: secondHalf,
    requested_by: userId,
    started_at: new Date().toISOString(),
    finished_at: null,
  });

  // Analiz birkaç dakika sürebilir; yanıt hemen döner, iş arka planda sürer.
  const task = run({
    matchId,
    videoId,
    home,
    away,
    goals,
    period,
    kickoff,
    secondHalf,
    kickoffAt: m.kickoff_at ?? null,
    secondHalfAt: m.second_half_at ?? null,
    limit: limits.perMatch,
    roster,
    autoPublish,
  });
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime;
  if (rt?.waitUntil) rt.waitUntil(task);
  else await task;

  return json({ ok: true, mode: timed ? "events" : "full", goals: goals.length }, 202);
});
