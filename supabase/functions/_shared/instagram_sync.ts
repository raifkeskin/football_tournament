// Bir turnuvanın bağlı Instagram hesabını eşitler: süresi yaklaşan belirteci
// yeniler ve (import_news açıksa) yeni gönderileri aktif sezona haber olarak
// ekler. instagram-sync (cron + "Haberlere aktar" anahtarı) ve
// instagram-oauth-callback (bağlanır bağlanmaz ilk aktarım) kullanır.
//
// Kurallar:
// * Görsel bağlantıları Instagram'da birkaç gün sonra geçersizleşir; görseller
//   media/news/ig/<turnuva>/ altına kopyalanır.
// * Çoklu gönderide en fazla 5 görsel (haber sınırı). Video/Reels'te kapak
//   görseli; video uygulamada Instagram'da açılır.
// * Görülen gönderi instagram_seen_media'ya yazılır, bir daha alınmaz (haber
//   silinse de). Tek seferde en fazla [MAX_PER_RUN] yeni gönderi alınır,
//   daha eskileri yalnızca görüldü sayılır — bağlanınca ya da anahtar uzun
//   süre kapalı kalıp açılınca Haberler eski gönderilerle dolmaz.

// deno-lint-ignore-file no-explicit-any
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const GRAPH = `https://graph.instagram.com/${Deno.env.get("INSTAGRAM_GRAPH_VERSION") ?? "v23.0"}`;
const MAX_PER_RUN = 10;
const MAX_IMAGES = 5;
const REFRESH_BEFORE_MS = 10 * 24 * 3600_000;
const DAY_MS = 24 * 3600_000;

export type IgAccount = {
  league_id: string;
  username: string | null;
  access_token: string;
  expires_at: string | null;
  connected_at: string;
  refreshed_at: string | null;
  import_news: boolean;
};

export const ACCOUNT_COLUMNS =
  "league_id, username, access_token, expires_at, connected_at, refreshed_at, import_news";

export type SyncResult = { league_id: string; imported: number; refreshed: boolean; error?: string };

function igError(body: any): string {
  return body?.error?.message ?? body?.error_message ?? JSON.stringify(body).slice(0, 300);
}

/** "2026-10-13T10:12:09+0000" → ISO (iki noktasız saat dilimi). */
function igTime(ts: string | undefined): string {
  if (!ts) return new Date().toISOString();
  const d = new Date(ts.replace(/([+-]\d{2})(\d{2})$/, "$1:$2"));
  return isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

async function refreshIfNeeded(admin: SupabaseClient, a: IgAccount): Promise<boolean> {
  if (!a.expires_at) return false;
  const exp = new Date(a.expires_at).getTime();
  const last = new Date(a.refreshed_at ?? a.connected_at).getTime();
  // Instagram yalnız 24 saatten eski ve süresi dolmamış belirteci yeniler.
  if (exp - Date.now() > REFRESH_BEFORE_MS || Date.now() - last < DAY_MS || exp < Date.now()) {
    return false;
  }
  const url = new URL("https://graph.instagram.com/refresh_access_token");
  url.searchParams.set("grant_type", "ig_refresh_token");
  url.searchParams.set("access_token", a.access_token);
  const res = await fetch(url);
  const body = await res.json();
  if (!res.ok || !body?.access_token) throw new Error(`Belirteç yenilenemedi: ${igError(body)}`);
  const now = new Date();
  a.access_token = body.access_token;
  a.expires_at = new Date(now.getTime() + Number(body.expires_in ?? 5184000) * 1000).toISOString();
  a.refreshed_at = now.toISOString();
  await admin.from("league_instagram_accounts").update({
    access_token: a.access_token,
    expires_at: a.expires_at,
    refreshed_at: a.refreshed_at,
  }).eq("league_id", a.league_id);
  return true;
}

/** Turnuvanın aktif sezonu; yoksa en yeni sezon. */
async function activeSeason(admin: SupabaseClient, leagueId: string): Promise<string | null> {
  const { data } = await admin
    .from("seasons")
    .select("id, is_active")
    .eq("league_id", leagueId)
    .is("deleted_at", null)
    .order("start_date", { ascending: false });
  if (!data || data.length === 0) return null;
  return (data.find((s: any) => s.is_active) ?? data[0]).id;
}

/** Gönderinin kopyalanacak görselleri (sırayla, en fazla 5). */
function imageSources(m: any): string[] {
  const one = (x: any) => (x?.media_type === "VIDEO" ? x?.thumbnail_url : x?.media_url) ?? x?.thumbnail_url;
  const list = m.media_type === "CAROUSEL_ALBUM"
    ? (m.children?.data ?? []).map(one)
    : [one(m)];
  return list.filter((u: any) => typeof u === "string" && u).slice(0, MAX_IMAGES);
}

async function copyImage(
  admin: SupabaseClient,
  src: string,
  path: string,
): Promise<string | null> {
  try {
    const res = await fetch(src);
    if (!res.ok) return null;
    const type = res.headers.get("content-type")?.split(";")[0] ?? "image/jpeg";
    const bytes = new Uint8Array(await res.arrayBuffer());
    const { error } = await admin.storage.from("media").upload(path, bytes, {
      contentType: type.startsWith("image/") ? type : "image/jpeg",
      cacheControl: "31536000",
      upsert: true,
    });
    if (error) {
      console.error("ig upload", path, error.message);
      return null;
    }
    return admin.storage.from("media").getPublicUrl(path).data.publicUrl;
  } catch (e) {
    console.error("ig image", e);
    return null;
  }
}

export async function syncAccount(admin: SupabaseClient, a: IgAccount): Promise<SyncResult> {
  const result: SyncResult = { league_id: a.league_id, imported: 0, refreshed: false };
  try {
    result.refreshed = await refreshIfNeeded(admin, a);
    if (!a.import_news) return result;

    const seasonId = await activeSeason(admin, a.league_id);
    if (!seasonId) throw new Error("Turnuvanın sezonu yok.");

    const url = new URL(`${GRAPH}/me/media`);
    url.searchParams.set(
      "fields",
      "id,caption,media_type,media_product_type,media_url,thumbnail_url,permalink,timestamp," +
        "children{media_type,media_url,thumbnail_url}",
    );
    url.searchParams.set("limit", "25");
    url.searchParams.set("access_token", a.access_token);
    const res = await fetch(url);
    const body = await res.json();
    if (!res.ok) throw new Error(`Gönderiler okunamadı: ${igError(body)}`);
    const media: any[] = body?.data ?? [];

    const ids = media.map((m) => String(m.id));
    const { data: seen } = ids.length
      ? await admin.from("instagram_seen_media").select("media_id")
        .eq("league_id", a.league_id).in("media_id", ids)
      : { data: [] as any[] };
    const seenSet = new Set((seen ?? []).map((r: any) => r.media_id));
    // Uygulamadan paylaşılan haberin kendisi geri gelmesin.
    const { data: own } = ids.length
      ? await admin.from("news").select("ig_media_id").in("ig_media_id", ids)
      : { data: [] as any[] };
    for (const r of own ?? []) seenSet.add(r.ig_media_id);

    // Instagram en yeniyi önce döner.
    const fresh = media.filter((m) => !seenSet.has(String(m.id)));
    const take = fresh.slice(0, MAX_PER_RUN).reverse(); // eskiden yeniye ekle
    const skip = fresh.slice(MAX_PER_RUN);

    for (const m of take) {
      const id = String(m.id);
      const urls: string[] = [];
      const srcs = imageSources(m);
      for (let i = 0; i < srcs.length; i++) {
        const u = await copyImage(admin, srcs[i], `news/ig/${a.league_id}/${id}_${i}.jpg`);
        if (u) urls.push(u);
      }
      const caption = String(m.caption ?? "").trim();
      const isVideo = m.media_type === "VIDEO";
      const { error } = await admin.from("news").insert({
        season_id: seasonId,
        content: caption || (isVideo ? "Instagram'da yeni video" : "Instagram'da yeni gönderi"),
        is_published: true,
        image_url: urls[0] ?? null,
        image_urls: urls,
        auto_kind: "instagram",
        ig_media_id: id,
        created_at: igTime(m.timestamp),
        auto_data: {
          permalink: m.permalink ?? null,
          video: isVideo,
          reel: m.media_product_type === "REELS",
          username: a.username,
        },
      });
      // Aynı gönderi zaten varsa (benzersiz dizin) yalnızca görüldü say.
      if (error && error.code !== "23505") throw new Error(`Haber eklenemedi: ${error.message}`);
      await admin.from("instagram_seen_media").upsert({ league_id: a.league_id, media_id: id });
      if (!error) result.imported++;
    }
    if (skip.length) {
      await admin.from("instagram_seen_media").upsert(
        skip.map((m) => ({ league_id: a.league_id, media_id: String(m.id) })),
      );
    }

    await admin.from("league_instagram_accounts")
      .update({ last_synced_at: new Date().toISOString(), last_error: null })
      .eq("league_id", a.league_id);
  } catch (e) {
    result.error = e instanceof Error ? e.message : String(e);
    console.error("ig sync", a.league_id, result.error);
    await admin.from("league_instagram_accounts")
      .update({ last_synced_at: new Date().toISOString(), last_error: result.error.slice(0, 500) })
      .eq("league_id", a.league_id);
  }
  return result;
}
