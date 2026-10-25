// Esame kağıdı okuma: takım sorumlusu / yetkili, el yazısı esame listesinin
// fotoğrafını yükler; Gemini satırları (forma no, ad soyad, doğum yılı, ilk
// 11 / yedek) okur ve her satırı o takımın sezon kadrosundan bir oyuncuyla
// eşleştirmeyi önerir. Kayıt yapılmaz: uygulama sonucu kontrol ekranında
// gösterir, kullanıcı onaylayınca esame formuna doldurur.
//
// Fotoğraf saklanmaz (yalnız bu istekte Gemini'ye gönderilir).
// Her çağrının maliyeti ai_usage_log'a (purpose = 'esame') yazılır; aylık YZ
// bütçesi (app_private_settings.ai_clip_monthly_usd) doluysa çağrı yapılmaz.
//
// Gizli değerler: GEMINI_API_KEY; isteğe bağlı ESAME_MODEL (varsayılan
// gemini-flash-latest; 2026-10-17 örnek kağıtta Flash ve Pro ikisi de 17/17
// doğru okudu, Flash ~6 kat ucuz). Zor el yazısında gemini-pro-latest.
//
// Yapay Zekâ Yönetimi'nden (app_private_settings):
//  * ai_thinking_esame: low (kısa düşünme, varsayılan) | high (uzun; zor
//    kâğıtta yeniden okuturken). Maliyetin çoğu düşünme kısmıdır.
//  * ai_esame_read_limit: bir maçta bir takımın esamesi en fazla kaç kez
//    okutulur (varsayılan 3; admin bu sınıra takılmaz).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { aiModel, refreshUsdTry, seasonAiEnabled } from "../_shared/ai_settings.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const ESAME_MODEL = Deno.env.get("ESAME_MODEL") ?? "gemini-flash-latest";

/** Modelin fiyatı ($ / 1M token): girdi, çıktı (düşünme dahil). */
function priceOf(model: string): [number, number] {
  return model.includes("flash") ? [0.5, 3.0] : [2.0, 12.0];
}
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// Fotoğraf sınırı (base64 öncesi yaklaşık 6 MB).
const MAX_BASE64 = 8_000_000;
// Bir okumanın tahmini en kötü maliyeti (bütçe kontrolü için).
const WORST_COST = 0.1;

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

const SCHEMA = {
  type: "OBJECT",
  properties: {
    takim: { type: "STRING", nullable: true },
    satirlar: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          forma: { type: "STRING", nullable: true },
          ad: { type: "STRING" },
          yil: { type: "INTEGER", nullable: true },
          bolum: { type: "STRING", enum: ["ilk11", "yedek"] },
          oyuncu: { type: "STRING", nullable: true },
        },
        required: ["ad", "bolum"],
      },
    },
  },
  required: ["satirlar"],
};

/** Türkçe harfleri sadeleştirip küçültür ("Çelebi" → "celebi"). */
function norm(s: string): string {
  return s.toLocaleLowerCase("tr").replace(/\(k\)/g, "")
    .replace(/[çc]/g, "c").replace(/[ğg]/g, "g").replace(/[ıi]/g, "i")
    .replace(/[öo]/g, "o").replace(/[şs]/g, "s").replace(/[üu]/g, "u")
    .replace(/[^a-z ]/g, "").replace(/\s+/g, " ").trim();
}

/** Levenshtein benzerliği (0..1). */
function sim(a: string, b: string): number {
  if (!a || !b) return 0;
  const d: number[] = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    let prev = d[0];
    d[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const t = d[j];
      d[j] = Math.min(d[j] + 1, d[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1));
      prev = t;
    }
  }
  return 1 - d[b.length] / Math.max(a.length, b.length);
}

async function monthlyLimit(): Promise<number> {
  const { data } = await admin.from("app_private_settings")
    .select("value").eq("key", "ai_clip_monthly_usd").maybeSingle();
  const v = Number(data?.value);
  return Number.isFinite(v) && v > 0 ? v : 5;
}

async function esameOptions(): Promise<{ thinking: string; limit: number }> {
  const { data } = await admin.from("app_private_settings")
    .select("key, value").in("key", ["ai_thinking_esame", "ai_esame_read_limit"]);
  // deno-lint-ignore no-explicit-any
  const get = (k: string) => String((data ?? []).find((r: any) => r.key === k)?.value ?? "");
  const limit = Number(get("ai_esame_read_limit"));
  return {
    thinking: get("ai_thinking_esame") === "high" ? "high" : "low",
    limit: Number.isFinite(limit) && limit > 0 ? limit : 3,
  };
}

async function spentThisMonth(): Promise<number> {
  const now = new Date();
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const { data } = await admin.from("ai_usage_log")
    .select("cost_usd").gte("created_at", monthStart.toISOString());
  return (data ?? []).reduce((a, r) => a + Number(r.cost_usd ?? 0), 0);
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
  const teamId = String(body?.team_id ?? "").trim();
  const image = String(body?.image_base64 ?? "");
  const mime = String(body?.mime ?? "image/jpeg");
  if (!matchId || !teamId || !image) {
    return json({ error: "match_id, team_id ve fotoğraf gerekli." }, 400);
  }
  if (image.length > MAX_BASE64) return json({ error: "Fotoğraf çok büyük." }, 413);
  if (!mime.startsWith("image/")) return json({ error: "Geçersiz dosya türü." }, 400);

  // Esameyi girebilen herkes okutabilir (yetkili, gözlemci, takım sorumlusu).
  const { data: allowed } = await userClient.rpc("can_edit_match_roster", {
    p_match_id: matchId,
    p_team_id: teamId,
  });
  if (allowed !== true) return json({ error: "Bu takımın esamesini girme yetkiniz yok." }, 403);

  // Model yalnız admin tarafından değiştirilebilir (karşılaştırma testi).
  // Model Yapay Zekâ Yönetimi'nden (flash / pro); yoksa ESAME_MODEL.
  const { data: isAdminRes } = await userClient.rpc("is_admin");
  const isAdmin = isAdminRes === true;
  let model = await aiModel(admin, "esame", ESAME_MODEL);
  const wanted = String(body?.model ?? "").trim();
  if (wanted && wanted !== model) {
    if (isAdmin && /^gemini-[a-z0-9.-]+$/.test(wanted)) model = wanted;
  }

  // Aynı esame sürekli okutulmasın: maç + takım başına sınır.
  const opts = await esameOptions();
  const { count: readCount } = await admin.from("ai_usage_log")
    .select("id", { count: "exact", head: true })
    .eq("purpose", "esame").eq("match_id", matchId).eq("team_id", teamId);
  const used = readCount ?? 0;
  if (!isAdmin && used >= opts.limit) {
    return json({
      error: `Bu takımın esamesi bu maç için ${opts.limit} kez okutuldu; ` +
        "okuma hakkı doldu. Esameyi elle düzenleyebilirsiniz.",
    }, 429);
  }

  if ((await spentThisMonth()) + WORST_COST > (await monthlyLimit())) {
    return json({ error: "Aylık YZ bütçesi doldu; esameyi elle girin." }, 429);
  }

  const { data: m } = await admin.from("matches")
    .select("season_id, home_team_id, away_team_id").eq("id", matchId).maybeSingle();
  if (!m) return json({ error: "Maç bulunamadı." }, 404);
  if (!(await seasonAiEnabled(admin, m.season_id, "esame"))) {
    return json({ error: "Bu sezonda kağıttan okuma kapalı; esameyi elle girin." }, 403);
  }
  await refreshUsdTry(admin);
  if (teamId !== m.home_team_id && teamId !== m.away_team_id) {
    return json({ error: "Takım bu maçta oynamıyor." }, 400);
  }

  const [{ data: team }, { data: squad }] = await Promise.all([
    admin.from("teams").select("name").eq("id", teamId).maybeSingle(),
    admin.from("season_team_players")
      .select("player_id, jersey_number, players(name, surname, birth_date)")
      .eq("season_id", m.season_id).eq("team_id", teamId).eq("is_active", true),
  ]);
  // deno-lint-ignore no-explicit-any
  const roster = (squad ?? []).map((r: any, i: number) => ({
    key: `P${i + 1}`,
    id: r.player_id as string,
    name: `${r.players?.name ?? ""} ${r.players?.surname ?? ""}`.trim(),
    year: r.players?.birth_date ? Number(String(r.players.birth_date).slice(0, 4)) : null,
    jersey: r.jersey_number ?? null,
  })).filter((p) => p.id && p.name);
  if (!roster.length) return json({ error: "Takımın bu sezon kadrosu boş." }, 400);

  const prompt = [
    "Bu fotoğraf amatör futbol turnuvasında el yazısıyla doldurulmuş bir ESAME LİSTESİ (maç kadrosu) formudur.",
    `Formun ait olması beklenen takım: "${team?.name ?? ""}".`,
    "Formdaki oyuncu satırlarını yukarıdan aşağıya oku. Her satır için:",
    "- forma: FORMA NO sütunundaki numara (yoksa null)",
    "- ad: ADI SOYADI sütununda yazanı olduğu gibi oku (Türkçe karakterlerle, tahmin ekleme)",
    "- yil: D.TARİHİ sütunundaki doğum yılı, dört haneli (okunmuyorsa null)",
    "- bolum: formda iki tablo varsa ilk tablodaki satırlar 'ilk11', ikinci tablodaki (ikinci FORMA NO başlığından sonraki) satırlar 'yedek'. Tek tablo varsa ilk 11 satır 'ilk11', kalanlar 'yedek'.",
    "- oyuncu: aşağıdaki kadroda bu satırla AYNI KİŞİ olan oyuncunun anahtarı (ör. P3). Ad, soyad ve doğum yılı birlikte uyuşmalı; el yazısındaki küçük farklar kabul. Emin değilsen veya kadroda yoksa null. Aynı anahtarı iki satıra verme.",
    "Boş satırları, takım sorumlusu, imza, skor ve kural metinlerini alma.",
    "takim: formdaki TAKIM ADI alanında yazan ad (okunmuyorsa null).",
    "",
    "Kadro (anahtar | ad soyad | doğum yılı | forma):",
    ...roster.map((p) => `${p.key} | ${p.name} | ${p.year ?? "-"} | ${p.jersey ?? "-"}`),
  ].join("\n");

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{
          role: "user",
          parts: [{ inlineData: { mimeType: mime, data: image } }, { text: prompt }],
        }],
        generationConfig: {
          temperature: 0,
          mediaResolution: "MEDIA_RESOLUTION_HIGH",
          responseMimeType: "application/json",
          responseSchema: SCHEMA,
          thinkingConfig: { thinkingLevel: opts.thinking },
        },
      }),
    },
  );
  const out = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = out?.error?.message ?? `HTTP ${res.status}`;
    return json({ error: `Okuma başarısız: ${msg}` }, 502);
  }

  const meta = out?.usageMetadata ?? {};
  const inTokens = Number(meta.promptTokenCount ?? 0);
  const outTokens = Number(meta.candidatesTokenCount ?? 0) + Number(meta.thoughtsTokenCount ?? 0);
  const [priceIn, priceOut] = priceOf(model);
  const cost = (inTokens * priceIn + outTokens * priceOut) / 1e6;
  await admin.from("ai_usage_log").insert({
    match_id: matchId,
    team_id: teamId,
    model,
    purpose: "esame",
    text_tokens: inTokens,
    output_tokens: outTokens,
    cost_usd: Number(cost.toFixed(5)),
  });

  const text: string = out?.candidates?.[0]?.content?.parts
    ?.map((p: { text?: string }) => p.text ?? "").join("") ?? "";
  // deno-lint-ignore no-explicit-any
  let data: any = {};
  try {
    data = JSON.parse(text || "{}");
  } catch {
    return json({ error: "Okuma sonucu çözülemedi; daha net bir fotoğraf deneyin." }, 502);
  }

  const byKey = new Map(roster.map((p) => [p.key, p.id]));
  const byId = new Map(roster.map((p) => [p.id, p]));
  const taken = new Set<string>();
  // deno-lint-ignore no-explicit-any
  const rows = (data?.satirlar ?? []).map((r: any) => {
    let pid = byKey.get(String(r?.oyuncu ?? "")) ?? null;
    if (pid && taken.has(pid)) pid = null;
    if (pid) taken.add(pid);
    return {
      jersey: r?.forma == null ? null : String(r.forma).trim() || null,
      name: String(r?.ad ?? "").trim(),
      year: Number.isFinite(Number(r?.yil)) && r?.yil ? Number(r.yil) : null,
      starting: r?.bolum !== "yedek",
      player_id: pid,
    };
  }).filter((r: { name: string }) => r.name);

  // Model eşleştiremediği satırlar: adı aynı, soyadı benzer ya da doğum yılı
  // ±1 olan kadro oyuncusu önerilir (el yazısında "Akar"/"Okan", 1978/1979).
  // Uygulama bu satırları "kontrol edin" diye gösterir.
  for (const r of rows) {
    if (r.player_id) continue;
    const [first, ...rest] = norm(r.name).split(" ");
    const sur = rest.join(" ");
    let best: { id: string; score: number } | null = null;
    let second = 0;
    for (const p of roster) {
      if (taken.has(p.id)) continue;
      const [pf, ...pr] = norm(p.name).split(" ");
      if (!first || pf !== first) continue;
      const surSim = sim(sur, pr.join(" "));
      const dy = r.year && p.year ? Math.abs(r.year - p.year) : null;
      if (dy != null && dy > 1) continue;
      if (surSim < 0.5 && dy == null) continue;
      const score = surSim + (dy === 0 ? 0.3 : dy === 1 ? 0.15 : 0);
      if (!best || score > best.score) {
        second = best?.score ?? 0;
        best = { id: p.id, score };
      } else if (score > second) second = score;
    }
    // Aynı adlı iki oyuncu birbirine çok yakınsa öneri yapılmaz.
    if (best && best.score - second >= 0.15 && byId.has(best.id)) {
      r.player_id = best.id;
      taken.add(best.id);
    }
  }

  return json({
    team_name: data?.takim ?? null,
    rows,
    model,
    thinking: opts.thinking,
    cost_usd: Number(cost.toFixed(4)),
    reads_left: isAdmin ? null : Math.max(0, opts.limit - used - 1),
  });
});
