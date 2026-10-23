// Yapay Zekâ Yönetimi ayarları (app_private_settings + seasons):
//  * aiModel: admin'in seçtiği model (flash / pro), her işlemde okunur.
//  * refreshUsdTry: TCMB dolar satış kuru günde bir kez güncellenir;
//    ai_usage_log tetikleyicisi TL maliyeti bu kurla yazar.
//  * seasonAiEnabled: sezonda özellik açık mı.
// deno-lint-ignore-file no-explicit-any

const MODELS: Record<string, string> = {
  flash: "gemini-flash-latest",
  pro: "gemini-pro-latest",
};

export async function aiModel(
  admin: any,
  purpose: "esame" | "clips",
  fallback: string,
): Promise<string> {
  const { data } = await admin.from("app_private_settings")
    .select("value").eq("key", `ai_model_${purpose}`).maybeSingle();
  return MODELS[String(data?.value ?? "")] ?? fallback;
}

/** TCMB kuru bugün güncellenmediyse günceller; hata olursa eski kur kalır. */
export async function refreshUsdTry(admin: any): Promise<void> {
  try {
    const { data } = await admin.from("app_private_settings")
      .select("value, updated_at").eq("key", "usd_try").maybeSingle();
    const last = data?.updated_at ? new Date(data.updated_at) : null;
    if (last && Date.now() - last.getTime() < 12 * 3600 * 1000) return;
    const res = await fetch("https://www.tcmb.gov.tr/kurlar/today.xml", {
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return;
    const xml = await res.text();
    const rate = xml.match(/Kod="USD"[\s\S]*?<ForexSelling>([\d.]+)<\/ForexSelling>/)?.[1];
    const day = xml.match(/Tarih="([\d.]+)"/)?.[1] ?? "";
    if (!rate || !(Number(rate) > 0)) return;
    const now = new Date().toISOString();
    await admin.from("app_private_settings").upsert([
      { key: "usd_try", value: rate, updated_at: now },
      { key: "usd_try_date", value: day, updated_at: now },
    ]);
  } catch (_) {
    // Kur alınamazsa son kayıtlı kur kullanılır.
  }
}

export async function seasonAiEnabled(
  admin: any,
  seasonId: string,
  feature: "esame" | "clips",
): Promise<boolean> {
  const col = feature === "esame" ? "ai_esame_enabled" : "ai_clips_enabled";
  const { data } = await admin.from("seasons")
    .select(`${col}, leagues(status, is_active)`)
    .eq("id", seasonId).maybeSingle();
  // Pasif turnuvada yapay zekâ işlemleri çalışmaz.
  const league = data?.leagues;
  if (league?.status === "passive" || league?.is_active === false) return false;
  return data?.[col] !== false;
}
