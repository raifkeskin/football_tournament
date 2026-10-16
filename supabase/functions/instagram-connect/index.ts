// Turnuvanın Instagram hesabını bağlama akışını başlatır.
//
// İstek: POST { league_id } — kullanıcının oturum belirteciyle; yalnızca
// owns_league() true olanlar (admin, kurucu başkan). Tek kullanımlık bir
// state üretip instagram_oauth_states'e yazar ve Instagram yetkilendirme
// adresini döner: { url }. Uygulama bu adresi tarayıcıda açar; Instagram
// kullanıcıyı instagram-oauth-callback'e geri yollar.
//
// Ortam: INSTAGRAM_APP_ID (isteğe bağlı; varsayılan LigMasasi Yayın-IG).

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const APP_ID = Deno.env.get("INSTAGRAM_APP_ID") ?? "1117446554321288";
const REDIRECT_URI = `${SUPABASE_URL}/functions/v1/instagram-oauth-callback`;
const SCOPES = ["instagram_business_basic", "instagram_business_content_publish"];

const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST bekleniyor." }, 405);

  let leagueId = "";
  try {
    leagueId = String((await req.json())?.league_id ?? "");
  } catch (_) {
    // boş gövde
  }
  if (!leagueId) return json({ error: "Turnuva seçilmedi." }, 400);

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user || user.is_anonymous) return json({ error: "Giriş yapmalısınız." }, 401);

  const { data: allowed } = await userClient.rpc("owns_league", { p_league_id: leagueId });
  if (allowed !== true) return json({ error: "Bu turnuva için yetkiniz yok." }, 403);

  // Eski (15 dk'dan uzun) state'leri temizle.
  await admin
    .from("instagram_oauth_states")
    .delete()
    .lt("created_at", new Date(Date.now() - 15 * 60_000).toISOString());

  const { data: row, error } = await admin
    .from("instagram_oauth_states")
    .insert({ league_id: leagueId, user_id: user.id })
    .select("state")
    .single();
  if (error || !row) {
    console.error("state insert", error);
    return json({ error: "Bağlantı başlatılamadı." }, 500);
  }

  const url = new URL("https://www.instagram.com/oauth/authorize");
  url.searchParams.set("enable_fb_login", "0");
  url.searchParams.set("force_authentication", "1");
  url.searchParams.set("client_id", APP_ID);
  url.searchParams.set("redirect_uri", REDIRECT_URI);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", SCOPES.join(","));
  url.searchParams.set("state", row.state);
  return json({ url: url.toString() });
});
