// Spor editörü haberi: maç öncesi / maç sonrası otomatik haberin metnini
// Gemini yazar. Veritabanındaki news_editor_notify tetikleyicisi çağırır
// (x-push-secret başlığı zorunlu). Yapay Zekâ Yönetimi'nden
// ai_news_pre_mode / ai_news_post_mode = off | flash | pro.
//  * Flash her zaman uzun düşünür (thinkingLevel high); Pro varsayılanla.
//  * Yazılan her isim / skor / dakika, verilen veriyle karşılaştırılır;
//    uyuşmazsa bir kez daha denenir, yine olmazsa haber değişmez.
//  * Elle düzenlenmiş manşet / metin ve aynı veriyle yeniden üretim korunur.
//  * Deneme: {match_id, kind: "pre"|"post", model, dry_run: true} metni yazmadan döndürür.
// deno-lint-ignore-file no-explicit-any

import { createClient } from "jsr:@supabase/supabase-js@2";
import { refreshUsdTry } from "../_shared/ai_settings.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const SECRET = Deno.env.get("PUSH_SECRET") ?? "";
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const MODELS: Record<string, string> = {
  flash: "gemini-flash-latest",
  pro: "gemini-pro-latest",
};
const PRICE: Record<string, [number, number]> = { flash: [0.5, 3.0], pro: [2.0, 12.0] };
const DAYS = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"];
const MONTHS = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// --- Yardımcılar -----------------------------------------------------------

async function fetchAll(build: () => any): Promise<any[]> {
  const out: any[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await build().range(from, from + 999);
    if (error) throw new Error(error.message);
    out.push(...(data ?? []));
    if ((data ?? []).length < 1000) break;
  }
  return out;
}

function dateText(d: string | null, t: string | null): string {
  if (!d) return "";
  const dt = new Date(d + "T12:00:00");
  return `${dt.getDate()} ${MONTHS[dt.getMonth()]} ${dt.getFullYear()} ${DAYS[dt.getDay()]}` +
    (t ? ` ${String(t).slice(0, 5)}` : "");
}

const when = (m: any) => `${m.match_date ?? ""} ${m.match_time ?? "00:00"}`;

type Row = { n: string; o: number; w: number; d: number; l: number; g: number; b: number; p: number };

function buildTable(matches: any[], names: Map<string, string>): (Row & { sira: number; id: string })[] {
  const T = new Map<string, Row>();
  for (const m of matches) {
    for (const [tid, f, a] of [
      [m.home_team_id, m.home_score, m.away_score],
      [m.away_team_id, m.away_score, m.home_score],
    ] as [string, number, number][]) {
      const r = T.get(tid) ?? { n: names.get(tid) ?? "", o: 0, w: 0, d: 0, l: 0, g: 0, b: 0, p: 0 };
      r.o++; r.g += f; r.b += a;
      if (f > a) { r.w++; r.p += 3; } else if (f === a) { r.d++; r.p++; } else r.l++;
      T.set(tid, r);
    }
  }
  return [...T.entries()]
    .sort((x, y) => y[1].p - x[1].p || (y[1].g - y[1].b) - (x[1].g - x[1].b) || y[1].g - x[1].g)
    .map(([id, r], i) => ({ id, sira: i + 1, ...r }));
}

function rowText(r: (Row & { sira: number }) | undefined) {
  if (!r) return null;
  return {
    sira: r.sira, oynanan: r.o, galibiyet: r.w, beraberlik: r.d, maglubiyet: r.l,
    atilan: r.g, yenilen: r.b, averaj: r.g - r.b, puan: r.p,
  };
}

/** Takımın son maçları (yeniden eskiye) ve güncel seri. */
function formOf(tid: string, finished: any[], names: Map<string, string>, limit = 5) {
  const list = finished
    .filter((m) => m.home_team_id === tid || m.away_team_id === tid)
    .sort((a, b) => when(b).localeCompare(when(a)))
    .slice(0, limit);
  const res = list.map((m) => {
    const home = m.home_team_id === tid;
    const f = home ? m.home_score : m.away_score;
    const a = home ? m.away_score : m.home_score;
    return {
      hafta: m.week,
      rakip: names.get(home ? m.away_team_id : m.home_team_id) ?? "",
      saha: home ? "ev" : "deplasman",
      skor: `${f}-${a}`,
      sonuc: f > a ? "G" : f === a ? "B" : "M",
    };
  });
  let seri = "";
  if (res.length) {
    const first = res[0].sonuc;
    let n = 0;
    for (const r of res) { if (r.sonuc === first) n++; else break; }
    if (first === "G") seri = `${n} maçtır kazanıyor`;
    else if (first === "M") seri = `${n} maçtır kaybediyor`;
    else seri = `${n} maçtır beraberlik`;
    let unb = 0;
    for (const r of res) { if (r.sonuc !== "M") unb++; else break; }
    if (first !== "M" && unb > n) seri += `, ${unb} maçtır yenilmiyor`;
    let win = 0;
    for (const r of res) { if (r.sonuc !== "G") win++; else break; }
    if (first !== "G" && win > n) seri += `, ${win} maçtır kazanamıyor`;
  }
  return { son_maclar: res, seri };
}

// --- Veri paketi -----------------------------------------------------------

async function buildPack(matchId: string, kind: "pre" | "post") {
  const { data: m, error } = await admin.from("matches").select(
    "id, season_id, group_id, week, match_date, match_time, status, home_score, away_score, referee_name, home_team_id, away_team_id, pitches(name), seasons(name, match_period_duration, leagues(name, status, is_active))",
  ).eq("id", matchId).maybeSingle();
  if (error || !m) throw new Error("Maç bulunamadı.");
  const league = (m as any).seasons?.leagues;
  if (league?.status === "passive" || league?.is_active === false) return null;
  const dur = Number((m as any).seasons?.match_period_duration) || 30;

  const all = await fetchAll(() => {
    let q = admin.from("matches").select(
      "id, week, match_date, match_time, status, home_score, away_score, home_team_id, away_team_id, group_id, pitches(name)",
    ).eq("season_id", m.season_id).is("deleted_at", null).order("id");
    if (m.group_id) q = q.eq("group_id", m.group_id);
    return q;
  });
  const teamIds = [...new Set(all.flatMap((x) => [x.home_team_id, x.away_team_id]))];
  const { data: teams } = await admin.from("teams").select("id, name").in("id", teamIds);
  const names = new Map<string, string>((teams ?? []).map((t: any) => [t.id, t.name]));

  const isFin = (x: any) => x.status === "finished" && x.home_score != null && x.away_score != null;
  const before = all.filter((x) => isFin(x) && x.id !== m.id && x.week < m.week);
  const upto = kind === "post"
    ? all.filter((x) => isFin(x) && x.week <= m.week)
    : before;

  // Olaylar
  const finIds = all.filter(isFin).map((x) => x.id);
  const events = finIds.length
    ? await fetchAll(() =>
      admin.from("match_events").select(
        "id, match_id, team_id, player_id, assist_player_id, event_type, minute, added_minute, is_own_goal, is_penalty",
      ).in("match_id", finIds).in("event_type", ["goal", "yellow_card", "red_card", "man_of_the_match"]).order("id")
    )
    : [];
  const pids = [...new Set(events.flatMap((e) => [e.player_id, e.assist_player_id]).filter(Boolean))];
  const pname = new Map<string, string>();
  for (let i = 0; i < pids.length; i += 150) {
    const { data: ps } = await admin.from("players").select("id, name, surname").in("id", pids.slice(i, i + 150));
    for (const p of ps ?? []) pname.set(p.id, `${p.name ?? ""} ${p.surname ?? ""}`.trim());
  }
  const goalsOf = (e: any) => e.event_type === "goal";
  const matchWeek = new Map(all.map((x) => [x.id, x.week]));

  function tally(maxWeekIncl: number, field: "player_id" | "assist_player_id", excludeMatch?: string) {
    const c = new Map<string, number>();
    for (const e of events) {
      if (!goalsOf(e) || (field === "player_id" && e.is_own_goal)) continue;
      const pid = e[field];
      if (!pid || e.match_id === excludeMatch) continue;
      if ((matchWeek.get(e.match_id) ?? 99) > maxWeekIncl) continue;
      c.set(pid, (c.get(pid) ?? 0) + 1);
    }
    return c;
  }
  const goalsBefore = tally(m.week - 1, "player_id");
  const goalsAfter = tally(m.week, "player_id");
  const assistsAfter = tally(m.week, "assist_player_id");
  const topScorers = (c: Map<string, number>) =>
    [...c.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([id, n]) => ({ oyuncu: pname.get(id) ?? "", gol: n }));

  const tableBefore = buildTable(before, names);
  const tableAfter = buildTable(upto, names);
  const hId = m.home_team_id, aId = m.away_team_id;
  const hn = names.get(hId) ?? "", an = names.get(aId) ?? "";

  const pack: any = {
    turnuva: league?.name ?? "",
    sezon: (m as any).seasons?.name ?? "",
    mac: {
      hafta: m.week,
      toplam_hafta: Math.max(...all.map((x) => x.week ?? 0)),
      tarih: dateText(m.match_date, m.match_time),
      saha: (m as any).pitches?.name ?? null,
      hakem: m.referee_name ?? null,
      ev_sahibi: hn,
      deplasman: an,
      devre_suresi_dk: dur,
    },
    ev_sahibi_takim: {
      ad: hn, puan_durumu_maci_oncesi: rowText(tableBefore.find((r) => r.id === hId)),
      ...formOf(hId, before, names),
    },
    deplasman_takim: {
      ad: an, puan_durumu_maci_oncesi: rowText(tableBefore.find((r) => r.id === aId)),
      ...formOf(aId, before, names),
    },
    puan_durumu_ilk3_maci_oncesi: tableBefore.slice(0, 3).map((r) => ({ sira: r.sira, takim: r.n, puan: r.p, oynanan: r.o })),
    takim_sayisi: teamIds.length,
    gol_krallari_maci_oncesi: topScorers(goalsBefore),
  };

  // Aynı iki takımın geçmiş karşılaşmaları (tüm sezonlar)
  const { data: h2h } = await admin.from("matches").select(
    "match_date, home_team_id, away_team_id, home_score, away_score, status",
  ).eq("status", "finished").is("deleted_at", null).neq("id", m.id)
    .or(`and(home_team_id.eq.${hId},away_team_id.eq.${aId}),and(home_team_id.eq.${aId},away_team_id.eq.${hId})`)
    .order("match_date", { ascending: false }).limit(5);
  pack.onceki_karsilasmalar = (h2h ?? []).map((x: any) => ({
    tarih: x.match_date,
    ev: names.get(x.home_team_id) ?? (x.home_team_id === hId ? hn : an),
    skor: `${x.home_score}-${x.away_score}`,
    deplasman: names.get(x.away_team_id) ?? (x.away_team_id === hId ? hn : an),
  }));

  if (kind === "pre") {
    const { data: w } = await admin.from("match_weather").select(
      "temp, feels_like, humidity, wind_kmh, pop, rain_mm, description",
    ).eq("match_id", m.id).maybeSingle();
    if (w) {
      pack.hava = {
        sicaklik_c: w.temp != null ? Math.round(Number(w.temp)) : null,
        hissedilen_c: w.feels_like != null ? Math.round(Number(w.feels_like)) : null,
        nem_yuzde: w.humidity ?? null,
        ruzgar_kmh: w.wind_kmh != null ? Math.round(Number(w.wind_kmh)) : null,
        yagis_ihtimali_yuzde: w.pop != null ? Math.round(Number(w.pop) * (Number(w.pop) <= 1 ? 100 : 1)) : null,
        yagis_mm: w.rain_mm ?? null,
        durum: w.description ?? null,
      };
    }
    return { pack, season: m.season_id, matchRow: m, names };
  }

  // Maç sonrası: olaylar ve sonuç
  const evs = events.filter((e) => e.match_id === m.id);
  const label = (e: any) => (e.added_minute ? `${e.minute}+${e.added_minute}` : `${e.minute}`);
  const ord = (e: any) => (e.minute ?? 0) * 100 + (e.added_minute ?? 0);
  const goals = evs.filter(goalsOf).sort((a, b) => ord(a) - ord(b));
  let hs = 0, as = 0;
  const flow: any[] = [];
  const scoreAt: string[] = ["0-0"];
  let leadChanges = 0, lastLeader = 0, trailedHome = false, trailedAway = false;
  for (const g of goals) {
    const forHome = g.is_own_goal ? g.team_id !== hId : g.team_id === hId;
    if (forHome) hs++; else as++;
    const leader = hs > as ? 1 : hs < as ? -1 : 0;
    if (leader !== 0 && lastLeader !== 0 && leader !== lastLeader) leadChanges++;
    if (leader !== 0) lastLeader = leader;
    if (hs < as) trailedHome = true;
    if (as < hs) trailedAway = true;
    scoreAt.push(`${hs}-${as}`);
    flow.push({
      dakika: label(g),
      devre: g.minute <= dur ? 1 : 2,
      golu_atan_takim: forHome ? hn : an,
      oyuncu: pname.get(g.player_id) ?? "",
      asist: pname.get(g.assist_player_id) ?? null,
      tur: g.is_own_goal ? "kendi kalesine" : g.is_penalty ? "penaltı" : "normal",
      skor_sonrasi: `${hs}-${as}`,
    });
  }
  const fh = goals.filter((g) => g.minute <= dur);
  const fhH = fh.filter((g) => (g.is_own_goal ? g.team_id !== hId : g.team_id === hId)).length;
  const comeback = (trailedHome && hs >= as) ? hn : (trailedAway && as >= hs) ? an : null;

  pack.sonuc = {
    skor: `${m.home_score}-${m.away_score}`,
    devre_arasi_skor: `${fhH}-${fh.length - fhH}`,
    ilk_yari_gol: fh.length,
    ikinci_yari_gol: goals.length - fh.length,
    skor_akisi: flow,
    liderlik_degisimi: leadChanges,
    geriden_gelip_beraberlik_veya_galibiyet_alan_takim: comeback,
    kartlar: evs.filter((e) => e.event_type !== "goal" && e.event_type !== "man_of_the_match").sort((a, b) => ord(a) - ord(b)).map((e) => ({
      dakika: label(e),
      kart: e.event_type === "red_card" ? "kırmızı" : "sarı",
      takim: e.team_id === hId ? hn : an,
      oyuncu: pname.get(e.player_id) ?? "",
    })),
    macin_oyuncusu: (() => {
      const e = evs.find((x) => x.event_type === "man_of_the_match");
      return e ? { oyuncu: pname.get(e.player_id) ?? "", takim: e.team_id === hId ? hn : an } : null;
    })(),
  };
  const scorerIds = [...new Set(goals.filter((g) => !g.is_own_goal).map((g) => g.player_id))];
  pack.golcu_ve_asistcilerin_sezon_toplamlari = [
    ...scorerIds.map((id) => ({
      oyuncu: pname.get(id) ?? "", bu_maca_kadar_sezon_golu: goalsBefore.get(id) ?? 0,
      mac_sonrasi_sezon_golu: goalsAfter.get(id) ?? 0, sezon_asisti: assistsAfter.get(id) ?? 0,
    })),
  ];
  pack.ev_sahibi_takim.seri_maci_sonrasi = formOf(hId, upto, names).seri;
  pack.deplasman_takim.seri_maci_sonrasi = formOf(aId, upto, names).seri;
  pack.ev_sahibi_takim.puan_durumu_maci_sonrasi = rowText(tableAfter.find((r) => r.id === hId));
  pack.deplasman_takim.puan_durumu_maci_sonrasi = rowText(tableAfter.find((r) => r.id === aId));
  pack.puan_durumu_ilk3_maci_sonrasi = tableAfter.slice(0, 3).map((r) => ({ sira: r.sira, takim: r.n, puan: r.p, oynanan: r.o }));
  pack.gol_krallari_maci_sonrasi = topScorers(goalsAfter);
  pack.haftanin_diger_sonuclari = all
    .filter((x) => isFin(x) && x.week === m.week && x.id !== m.id)
    .map((x) => `${names.get(x.home_team_id)} ${x.home_score}-${x.away_score} ${names.get(x.away_team_id)}`);

  // Sonraki maçlar
  const todayStr = new Date().toISOString().slice(0, 10);
  const next = (tid: string) => {
    const x = all
      .filter((y) => !isFin(y) && y.id !== m.id && y.week > m.week && (y.home_team_id === tid || y.away_team_id === tid) && y.match_date && y.match_date >= todayStr)
      .sort((a, b) => when(a).localeCompare(when(b)))[0];
    if (!x) return null;
    const opp = x.home_team_id === tid ? x.away_team_id : x.home_team_id;
    return {
      hafta: x.week,
      tarih: dateText(x.match_date, x.match_time),
      saha: x.pitches?.name ?? null,
      rakip: names.get(opp) ?? "",
      takimin_sahasi: x.home_team_id === tid ? "ev sahibi" : "deplasman",
      rakibin_durumu: rowText(tableAfter.find((r) => r.id === opp)),
    };
  };
  pack.ev_sahibi_takim.sonraki_mac = next(hId);
  pack.deplasman_takim.sonraki_mac = next(aId);
  return { pack, season: m.season_id, matchRow: m, names };
}

// --- Gemini ----------------------------------------------------------------

const SYSTEM = `Sen Türkiye spor basınında deneyimli bir yayın editörüsün. Amatör bir turnuva için haber yazıyorsun. Sana JSON olarak maç verisi verilecek.
Kurallar:
- Yalnızca verilen veriyi kullan. Verilmeyen isim, sayı, dakika, pozisyon, oyun anlatımı UYDURMA. "Baskı kurdu", "direkten döndü", "tribünler" gibi veride olmayan şeyleri yazma.
- Turnuva adını verildiği gibi yaz, çevirme. Takım ve oyuncu adlarını verildiği gibi (ad soyad) yaz. Skor yazımı 2-1 biçiminde.
- Üslup: akıcı, canlı, futbol terimlerine uygun spor basını dili (ilk yarı, ikinci yarı, uzatma dakikaları, averaj, hat-trick, asist, skor yarışı, geriye düşüp dönmek, liderlik...). Klişe ve abartıdan kaçın; sıralama, seri, sezon golü, önceki karşılaşma gibi veriden çıkan yorumları kat. Asist veren oyuncuları adıyla an.
- 70+3 gibi gösterimler uzatma dakikalarıdır. 'devre_suresi_dk' bir devrenin süresidir.
- Manşet normal cümle düzeninde yazılır (tamamı büyük harf olmaz), en çok 110 karakter.
- Takım renkleri, lakap, kadro, taraftar, tarihçe gibi veride olmayan hiçbir bilgiyi ekleme (örneğin takım adından renk çıkarma).
- Yapay zekâdan söz etme.
- Maç sonrası haberinde son paragrafa iki takımın sonraki maçını (tarih, rakip, rakibin durumu) kısaca ekle; veri yoksa ekleme.
- Maç öncesi haberde 'hava' verisi varsa sıcaklık, rüzgâr ve yağış ihtimalini maçın oynanacağı koşullar olarak bir cümleyle an; yoksa hava durumundan söz etme.
- Maç öncesi haberde sonuç tahmini yapma; iki takımın durumunu, formunu, önceki karşılaşmalarını, gol yarışını ve maçın yerini/zamanını anlat.
Çıktı JSON: {"manset": string, "spot": string (1-2 cümle), "paragraflar": string[] (3-5 paragraf, toplam 140-220 kelime)}`;

const SCHEMA = {
  type: "OBJECT",
  properties: {
    manset: { type: "STRING" },
    spot: { type: "STRING" },
    paragraflar: { type: "ARRAY", items: { type: "STRING" } },
  },
  required: ["manset", "spot", "paragraflar"],
};

async function gemini(model: "flash" | "pro", kind: "pre" | "post", pack: any) {
  const gen: any = {
    temperature: 0.7,
    responseMimeType: "application/json",
    responseSchema: SCHEMA,
  };
  if (model === "flash") gen.thinkingConfig = { thinkingLevel: "high" };
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODELS[model]}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM }] },
        contents: [{
          role: "user",
          parts: [{
            text: (kind === "pre" ? "MAÇ ÖNCESİ HABERİ yaz (maç henüz oynanmadı; sonuç bilinmiyor).\n" : "MAÇ SONRASI HABERİ yaz.\n") +
              JSON.stringify(pack),
          }],
        }],
        generationConfig: gen,
      }),
    },
  );
  if (!res.ok) throw new Error(`Gemini ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const j = await res.json();
  const text = (j.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? "").join("");
  const u = j.usageMetadata ?? {};
  const [pi, po] = PRICE[model];
  const inTok = Number(u.promptTokenCount ?? 0);
  const outTok = Number(u.candidatesTokenCount ?? 0) + Number(u.thoughtsTokenCount ?? 0);
  return {
    out: JSON.parse(text) as { manset: string; spot: string; paragraflar: string[] },
    inTok, outTok, cost: (inTok * pi + outTok * po) / 1e6,
  };
}

/** Metindeki skor ve dakikalar veri paketinde yoksa hata metni döner. */
function check(out: { manset: string; spot: string; paragraflar: string[] }, pack: any): string | null {
  const text = [out.manset, out.spot, ...out.paragraflar].join(" ");
  if (!out.manset?.trim() || !out.paragraflar?.length) return "boş metin";
  const raw = JSON.stringify(pack).replace(/–/g, "-");
  const scores = new Set<string>();
  for (const s of raw.matchAll(/(\d{1,2})-(\d{1,2})/g)) { scores.add(`${s[1]}-${s[2]}`); scores.add(`${s[2]}-${s[1]}`); }
  for (const s of text.replace(/–/g, "-").matchAll(/(?<![\d.])(\d{1,2})-(\d{1,2})(?![\d])/g)) {
    if (!scores.has(`${s[1]}-${s[2]}`)) return `pakette olmayan skor: ${s[0]}`;
  }
  const mins = new Set<string>();
  for (const d of raw.matchAll(/"dakika":"(\d{1,3})(?:\+(\d{1,2}))?"/g)) { mins.add(d[1]); if (d[2]) mins.add(`${d[1]}+${d[2]}`); }
  // Dakika: "7. dakikada", "53'te", "70+4'te". Saat (20:30'da), skor (3-3'e)
  // ve devre süresi (35'er dakika) dakika sayılmaz.
  const half = Number(pack?.mac?.devre_suresi_dk) || 0;
  for (const d of text.matchAll(/(?<![\d:\-+])(\d{1,3})(\+\d{1,2})?(?:['’]|\.\s*dakika)/g)) {
    const full = d[1] + (d[2] ?? "");
    if (!mins.has(full) && !mins.has(d[1]) && Number(d[1]) !== half && Number(d[1]) !== half * 2) {
      return `pakette olmayan dakika: ${d[0]}`;
    }
  }
  return null;
}

// --- İstek -----------------------------------------------------------------

Deno.serve(async (req) => {
  if (!SECRET || req.headers.get("x-push-secret") !== SECRET) return json({ error: "yetkisiz" }, 401);
  if (!GEMINI_API_KEY) return json({ error: "GEMINI_API_KEY ayarlı değil." }, 500);
  try {
    const body = await req.json();
    const dry = body.dry_run === true;
    let news: any = null;
    let matchId: string = body.match_id ?? "";
    let kind: "pre" | "post" = body.kind === "pre" ? "pre" : "post";
    let model: "flash" | "pro" = body.model === "pro" ? "pro" : "flash";

    if (body.news_id) {
      const { data } = await admin.from("news").select(
        "id, auto_kind, match_id, headline, article, deck, editor_meta",
      ).eq("id", body.news_id).maybeSingle();
      news = data;
      if (!news?.match_id) return json({ skipped: "haber yok" });
      matchId = news.match_id;
      kind = news.auto_kind === "match_preview" ? "pre" : "post";
    }
    if (!dry) {
      if (!news) return json({ error: "news_id gerekli" }, 400);
      const { data: s } = await admin.from("app_private_settings").select("value")
        .eq("key", kind === "pre" ? "ai_news_pre_mode" : "ai_news_post_mode").maybeSingle();
      const mode = String(s?.value ?? "off");
      if (mode !== "flash" && mode !== "pro") return json({ skipped: "kapalı" });
      model = mode;
    }

    const built = await buildPack(matchId, kind);
    if (!built) return json({ skipped: "pasif turnuva" });
    // Hava durumu sık güncellenir; yeniden yazım tetiklemesin diye özetten çıkar.
    const { hava: _hava, ...stable } = built.pack;
    const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(stable) + model))
      .then((b) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("").slice(0, 24));

    if (!dry) {
      const meta = news.editor_meta ?? null;
      if (meta?.hash === hash) return json({ skipped: "aynı veri" });
      const hasText = (news.headline ?? "") !== "" || (news.article ?? "") !== "";
      if (hasText && (!meta || meta.headline !== news.headline || meta.article !== news.article)) {
        return json({ skipped: "elle düzenlenmiş" });
      }
    }

    await refreshUsdTry(admin);
    let attempt = await gemini(model, kind, built.pack);
    let err = check(attempt.out, built.pack);
    let cost = attempt.cost, inTok = attempt.inTok, outTok = attempt.outTok;
    if (err) {
      const again = await gemini(model, kind, built.pack);
      cost += again.cost; inTok += again.inTok; outTok += again.outTok;
      const err2 = check(again.out, built.pack);
      attempt = again;
      err = err2;
    }
    if (!dry) {
      await admin.from("ai_usage_log").insert({
        match_id: matchId, model: MODELS[model], purpose: kind === "pre" ? "news_pre" : "news_post",
        text_tokens: inTok, output_tokens: outTok, cost_usd: Number(cost.toFixed(5)),
      });
    }
    const o = attempt.out;
    const headline = o.manset.trim().slice(0, 140);
    const deck = o.spot.trim().slice(0, 600);
    const article = o.paragraflar.map((p) => p.trim()).filter(Boolean).join("\n\n").slice(0, 4000);
    if (dry) return json({ headline, deck, article, check: err, cost, inTok, outTok, model, pack: body.include_pack ? built.pack : undefined });
    if (err) {
      await admin.from("news").update({ editor_meta: { hash, error: err, at: new Date().toISOString() } }).eq("id", news.id);
      console.error("news-editor doğrulama", err);
      return json({ skipped: "doğrulama", err });
    }
    const upd: any = {
      headline, deck, article,
      editor_meta: { hash, kind, model, headline, article, deck, at: new Date().toISOString() },
    };
    // Maç sonrası yazı onaya düşer: kurucu / sorumlu inceler, onaylanmazsa
    // 1 saat sonra kendiliğinden yayınlanır (haber onayı açıksa).
    if (kind === "post") {
      const { data: ap } = await admin.from("app_settings").select("value").eq("key", "news_approval_enabled").maybeSingle();
      if (ap?.value === true && !(news.editor_meta?.hash)) {
        upd.is_published = false;
        upd.pending_until = new Date(Date.now() + 60 * 60 * 1000).toISOString();
      }
    }
    await admin.from("news").update(upd).eq("id", news.id);
    return json({ ok: true, cost });
  } catch (e) {
    console.error("news-editor", (e as Error).message);
    return json({ error: (e as Error).message }, 500);
  }
});
