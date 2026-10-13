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
// GEMINI_MODEL (varsayılan gemini-flash-latest) ve 1M token başına USD
// fiyatlar GEMINI_PRICE_INPUT (görüntü+metin, 0.5), GEMINI_PRICE_AUDIO (1.0),
// GEMINI_PRICE_OUTPUT (3.0).

import { createClient } from "jsr:@supabase/supabase-js@2";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-flash-latest";
const PRICE_INPUT = Number(Deno.env.get("GEMINI_PRICE_INPUT") ?? "0.5");
const PRICE_AUDIO = Number(Deno.env.get("GEMINI_PRICE_AUDIO") ?? "1.0");
const PRICE_OUTPUT = Number(Deno.env.get("GEMINI_PRICE_OUTPUT") ?? "3.0");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

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
  minute: number;
  teamId: string | null;
  teamName: string;
  player: string;
  ownGoal: boolean;
  penalty: boolean;
};

type Window = { start: number; end: number; goals: GoalEvent[] };

type FoundGoal = {
  olay_no?: number | null;
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
  return (video * PRICE_INPUT + audio * PRICE_AUDIO + OUTPUT_TOKENS_GUESS * PRICE_OUTPUT) / 1e6;
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
  const cost = ((text + video) * PRICE_INPUT + audio * PRICE_AUDIO + output * PRICE_OUTPUT) / 1e6;
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
          guven: { type: "STRING", enum: ["yuksek", "orta", "dusuk"] },
        },
        required: ["gol_ani", "guven"],
      },
    },
  },
  required: ["goller"],
};

function goalsPrompt(home: string, away: string, window: Window | null, goals: GoalEvent[]) {
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
    lines.push("Tüm videoyu tara; zamanları videonun başından itibaren yaz.", "");
  }
  if (goals.length) {
    lines.push(
      window
        ? "Maç raporuna göre bu aralıkta şu goller var (dakika maç dakikasıdır, video zamanı değil):"
        : "Maç raporundaki goller (dakika maç dakikasıdır, video zamanı değil):",
    );
    for (const g of goals) {
      const extra = g.ownGoal ? " (kendi kalesine)" : g.penalty ? " (penaltı)" : "";
      lines.push(
        `- olay_no ${g.no}: ${g.minute}' ${g.teamName}${g.player ? ` – ${g.player}` : ""}${extra}`,
      );
    }
    lines.push(
      "Bu golleri videoda bul ve her biri için olay_no'yu yaz. Raporda olmayan",
      "bir gol görürsen olay_no'yu boş bırakarak ekle.",
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
    "- aciklama: kısa Türkçe açıklama (oyuncu adı anlatımda geçiyorsa kullan)",
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
): Window[] {
  const raw: Window[] = goals.map((g) => {
    const firstHalf = g.minute <= period;
    let center: number;
    let before = NARROW;
    let after = NARROW;
    if (!firstHalf && secondHalf != null) {
      center = secondHalf + (g.minute - period) * 60;
    } else {
      center = (kickoff ?? 0) + g.minute * 60;
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
  limit: number;
};

/** Videonun yaklaşık süresi (sn): başlangıç + iki devre + devre arası. */
function approxVideoLength(period: number, kickoff: number | null) {
  return (kickoff ?? 0) + (2 * period) * 60 + HALFTIME_SLACK;
}

async function run(opts: RunOpts) {
  const { matchId, videoId, home, away, goals, period } = opts;
  const budget = new Budget(matchId, opts.limit);
  let { kickoff, secondHalf } = opts;
  try {
    // 1) Başlangıçlar verilmediyse YZ bulur (yalnızca gerektiğinde).
    if (goals.length) {
      if (kickoff == null) {
        kickoff = await detectStart(budget, videoId, "kickoff", 0, 1200);
      }
      const needSecond = secondHalf == null && goals.some((g) => g.minute > period);
      if (needSecond && kickoff != null) {
        const from = kickoff + period * 60;
        secondHalf = await detectStart(budget, videoId, "second_half", from, from + 1500);
      }
      await admin.from("match_highlight_jobs")
        .update({ kickoff_sec: kickoff, second_half_sec: secondHalf })
        .eq("match_id", matchId);
    }

    // 2) Taranacak aralıklar; 3) tavan: büyük kısmı kaplıyorsa tüm video.
    let windows: (Window | null)[] = goals.length
      ? buildWindows(goals, period, kickoff, secondHalf)
      : [null];
    const covered = windows.reduce((a, w) => a + (w ? w.end - w.start : 0), 0);
    const total = approxVideoLength(period, kickoff);
    if (goals.length && covered > total * 0.7) windows = [null];

    const plannedCost = windows.reduce(
      (a, w) => a + estimateCost(w ? w.end - w.start : total),
      0,
    );
    budget.ensure(plannedCost);

    const results = await Promise.all(
      windows.map(async (w) => {
        const { data, usage } = await askGemini({
          videoId,
          prompt: goalsPrompt(home.name, away.name, w, w ? w.goals : goals),
          schema: GOALS_SCHEMA,
          start: w?.start,
          end: w?.end,
        });
        await budget.record(w ? "goals" : "full", usage);
        const found = Array.isArray(data.goller) ? (data.goller as FoundGoal[]) : [];
        return { w, found };
      }),
    );

    const rows: Record<string, unknown>[] = [];
    const usedEvents = new Set<string>();
    const seenSec: number[] = [];
    for (const { w, found } of results) {
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

        const ev = f.olay_no != null
          ? goals.find((g) => g.no === f.olay_no && !usedEvents.has(g.id))
          : undefined;
        if (ev) usedEvents.add(ev.id);

        const teamName = (f.atan_takim ?? "").toLocaleLowerCase("tr");
        const teamId = ev
          ? (ev.ownGoal ? (ev.teamId === home.id ? away.id : home.id) : ev.teamId)
          : teamName && home.name.toLocaleLowerCase("tr").includes(teamName)
          ? home.id
          : teamName && away.name.toLocaleLowerCase("tr").includes(teamName)
          ? away.id
          : null;

        const minuteRaw = ev?.minute ?? parseInt(String(f.mac_dakikasi ?? ""), 10);
        rows.push({
          match_id: matchId,
          kind: "goal",
          match_event_id: ev?.id ?? null,
          team_id: teamId,
          minute: Number.isFinite(minuteRaw) ? minuteRaw : null,
          video_id: videoId,
          start_sec: start,
          end_sec: end,
          description: (f.aciklama ?? "").trim() || null,
          confidence: CONFIDENCE[f.guven ?? ""] ?? null,
          status: "pending",
          source: "ai",
        });
      }
    }

    // Yeniden çalıştırmada eski bekleyen YZ kesitleri silinir (onaylılar kalır).
    await admin.from("match_highlights").delete()
      .eq("match_id", matchId).eq("status", "pending").eq("source", "ai");
    if (rows.length) {
      const { error } = await admin.from("match_highlights").insert(rows);
      if (error) throw new Error(error.message);
    }
    await admin.from("match_highlight_jobs").update({
      status: "done",
      mode: windows[0] == null ? "full" : "events",
      found: rows.length,
      cost_usd: Number(budget.spent.toFixed(5)),
      finished_at: new Date().toISOString(),
    }).eq("match_id", matchId);
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
  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) return json({ error: "Giriş gerekli." }, 401);

  const body = await req.json().catch(() => ({}));
  const matchId = String(body?.match_id ?? "").trim();
  if (!matchId) return json({ error: "match_id eksik." }, 400);
  const kickoff = toSec(body?.kickoff_sec);
  const secondHalf = toSec(body?.second_half_sec);

  const { data: allowed } = await userClient.rpc("owns_match", { p_match_id: matchId });
  if (allowed !== true) return json({ error: "Bu maç için yetkiniz yok." }, 403);

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
    .select("id, season_id, home_team_id, away_team_id").eq("id", matchId).maybeSingle();
  if (!m) return json({ error: "Maç bulunamadı." }, 404);

  const { data: links } = await admin.from("match_media")
    .select("url, created_at").eq("match_id", matchId).eq("media_type", "Maç Yayın Linki")
    .order("created_at", { ascending: false });
  const videoId = (links ?? []).map((l) => youtubeId(l.url ?? "")).find((x) => x) ?? null;
  if (!videoId) return json({ error: "Maçın YouTube yayın linki yok." }, 400);

  const [{ data: teams }, { data: season }, { data: events }] = await Promise.all([
    admin.from("teams").select("id, name").in("id", [m.home_team_id, m.away_team_id]),
    admin.from("seasons").select("match_period_duration").eq("id", m.season_id).maybeSingle(),
    admin.from("match_events")
      .select("id, minute, team_id, player_name, is_own_goal, is_penalty")
      .eq("match_id", matchId).eq("event_type", "goal").order("minute"),
  ]);
  const nameOf = (id: string) => (teams ?? []).find((t) => t.id === id)?.name ?? "";
  const home = { id: m.home_team_id, name: nameOf(m.home_team_id) || "Ev sahibi" };
  const away = { id: m.away_team_id, name: nameOf(m.away_team_id) || "Deplasman" };
  const period = Number(season?.match_period_duration) > 0
    ? Number(season!.match_period_duration)
    : 45;

  const goals: GoalEvent[] = (events ?? []).map((e, i) => ({
    no: i + 1,
    id: e.id,
    minute: Number(e.minute) || 0,
    teamId: e.team_id,
    teamName: e.team_id === home.id ? home.name : e.team_id === away.id ? away.name : "",
    player: (e.player_name ?? "").trim(),
    ownGoal: !!e.is_own_goal,
    penalty: !!e.is_penalty,
  }));

  // Sınırlar: en kötü durum tahmini (başlangıç bulunamazsa geniş pencereler
  // ya da tüm video) maç başı veya aylık sınırı aşıyorsa Gemini'ye gidilmez.
  const limits = await readLimits();
  const total = approxVideoLength(period, kickoff);
  const detectCost = goals.length
    ? (kickoff == null ? estimateCost(1200, DETECT_FPS) : 0) +
      (secondHalf == null ? estimateCost(1500, DETECT_FPS) : 0)
    : 0;
  const worstWindows = goals.length ? buildWindows(goals, period, kickoff, secondHalf) : [];
  const worstScan = goals.length
    ? Math.min(
      worstWindows.reduce((a, w) => a + estimateCost(w.end - w.start), 0),
      estimateCost(total),
    )
    : estimateCost(total);
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
    mode: goals.length ? "events" : "full",
    model: GEMINI_MODEL,
    found: null,
    error: null,
    cost_usd: 0,
    kickoff_sec: kickoff,
    second_half_sec: secondHalf,
    requested_by: userData.user.id,
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
    limit: limits.perMatch,
  });
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime;
  if (rt?.waitUntil) rt.waitUntil(task);
  else await task;

  return json({ ok: true, mode: goals.length ? "events" : "full", goals: goals.length }, 202);
});
