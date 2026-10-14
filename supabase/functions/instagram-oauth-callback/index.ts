// Instagram yetkilendirmesinden dönüş (OAuth redirect URI). JWT doğrulaması
// kapalı yayınlanır: `supabase functions deploy instagram-oauth-callback
// --no-verify-jwt` — isteği Instagram'ın yönlendirdiği tarayıcı yapar.
//
// Akış: state'i doğrula ve sil → code'u kısa ömürlü belirtece çevir → uzun
// ömürlü (60 gün) belirtece çevir → /me ile hesap kimliği ve kullanıcı adı →
// league_instagram_accounts'a yaz → son gönderileri arka planda Haberler'e
// aktar (import_news açıksa). Sonunda kullanıcıyı web uygulamasındaki
// /instagram-baglandi sayfasına yönlendirir (Supabase alan adında HTML
// sunulamıyor).
//
// Gizli değerler (supabase secrets): INSTAGRAM_APP_SECRET; isteğe bağlı
// INSTAGRAM_APP_ID, INSTAGRAM_GRAPH_VERSION (varsayılan v23.0), APP_WEB_URL
// (varsayılan https://masterfutbol.web.app).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { ACCOUNT_COLUMNS, type IgAccount, syncAccount } from "../_shared/instagram_sync.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const APP_ID = Deno.env.get("INSTAGRAM_APP_ID") ?? "1117446554321288";
const APP_SECRET = Deno.env.get("INSTAGRAM_APP_SECRET") ?? "";
const GRAPH = `https://graph.instagram.com/${Deno.env.get("INSTAGRAM_GRAPH_VERSION") ?? "v23.0"}`;
const WEB_URL = Deno.env.get("APP_WEB_URL") ?? "https://masterfutbol.web.app";
const REDIRECT_URI = `${SUPABASE_URL}/functions/v1/instagram-oauth-callback`;
const STATE_TTL_MS = 15 * 60_000;

const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

function done(params: Record<string, string>) {
  const url = new URL(`${WEB_URL}/instagram-baglandi`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return new Response(null, { status: 302, headers: { Location: url.toString() } });
}

function fail(reason: string, detail?: unknown) {
  if (detail !== undefined) console.error(reason, detail);
  return done({ durum: "hata", neden: reason });
}

/** Instagram yanıtındaki hata metni. */
function igError(body: any): string {
  return body?.error_message ?? body?.error?.message ?? JSON.stringify(body);
}

Deno.serve(async (req) => {
  const q = new URL(req.url).searchParams;

  // Kullanıcı izin ekranında vazgeçti.
  if (q.get("error")) return done({ durum: "iptal" });

  const state = q.get("state") ?? "";
  // Instagram code'un sonuna "#_" ekleyebiliyor.
  const code = (q.get("code") ?? "").replace(/#_$/, "");
  if (!state || !code) return fail("eksik");
  if (!APP_SECRET) return fail("ayar", "INSTAGRAM_APP_SECRET tanımlı değil");

  // State tek kullanımlık: okurken sil.
  const { data: st } = await admin
    .from("instagram_oauth_states")
    .delete()
    .eq("state", state)
    .select("league_id, user_id, created_at")
    .maybeSingle();
  if (!st) return fail("gecersiz");
  if (Date.now() - new Date(st.created_at).getTime() > STATE_TTL_MS) return fail("sure");

  try {
    // 1) code → kısa ömürlü belirteç
    const shortRes = await fetch("https://api.instagram.com/oauth/access_token", {
      method: "POST",
      body: new URLSearchParams({
        client_id: APP_ID,
        client_secret: APP_SECRET,
        grant_type: "authorization_code",
        redirect_uri: REDIRECT_URI,
        code,
      }),
    });
    const shortBody = await shortRes.json();
    // Yeni biçim { data: [ {...} ] }, eski biçim düz nesne.
    const short = Array.isArray(shortBody?.data) ? shortBody.data[0] : shortBody;
    if (!shortRes.ok || !short?.access_token) return fail("kod", igError(shortBody));

    let perms: string[] = Array.isArray(short.permissions)
      ? short.permissions
      : String(short.permissions ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    // Yanıtta izin listesi yoksa istenen izinler verilmiş sayılır.
    if (perms.length === 0) perms = ["instagram_business_basic", "instagram_business_content_publish"];

    // 2) kısa → uzun ömürlü (60 gün)
    const longUrl = new URL("https://graph.instagram.com/access_token");
    longUrl.searchParams.set("grant_type", "ig_exchange_token");
    longUrl.searchParams.set("client_secret", APP_SECRET);
    longUrl.searchParams.set("access_token", short.access_token);
    const longRes = await fetch(longUrl);
    const long = await longRes.json();
    if (!longRes.ok || !long?.access_token) return fail("uzun", igError(long));

    // 3) hesap bilgisi
    const meUrl = new URL(`${GRAPH}/me`);
    meUrl.searchParams.set("fields", "user_id,username");
    meUrl.searchParams.set("access_token", long.access_token);
    const meRes = await fetch(meUrl);
    const me = await meRes.json();
    if (!meRes.ok) return fail("hesap", igError(me));

    const expiresAt = long.expires_in
      ? new Date(Date.now() + Number(long.expires_in) * 1000).toISOString()
      : null;

    const { error } = await admin.from("league_instagram_accounts").upsert({
      league_id: st.league_id,
      ig_user_id: String(me.user_id ?? me.id ?? short.user_id),
      username: me.username ?? null,
      access_token: long.access_token,
      expires_at: expiresAt,
      permissions: perms,
      connected_by: st.user_id,
      connected_at: new Date().toISOString(),
      refreshed_at: null,
      last_error: null,
    });
    if (error) return fail("kayit", error);

    // İlk aktarım yönlendirmeyi bekletmesin.
    const firstSync = admin
      .from("league_instagram_accounts")
      .select(ACCOUNT_COLUMNS)
      .eq("league_id", st.league_id)
      .single()
      .then(({ data }) => data ? syncAccount(admin, data as IgAccount) : null);
    if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(firstSync);

    const canPublish = perms.includes("instagram_business_content_publish");
    return done({
      durum: canPublish ? "ok" : "izin",
      kullanici: me.username ?? "",
    });
  } catch (e) {
    return fail("ag", e);
  }
});
