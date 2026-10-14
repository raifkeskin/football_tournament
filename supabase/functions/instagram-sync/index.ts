// Bağlı Instagram hesaplarını eşitler (bkz. _shared/instagram_sync.ts).
//
// İki çağrı biçimi:
// * Cron (instagram_sync_tick, 15 dk): `x-sync-secret` başlığı
//   app_private_settings.instagram_sync_secret ile aynı → tüm hesaplar.
// * Uygulama ("Haberlere aktar" açılınca): kullanıcının oturum belirteci +
//   { league_id }; yalnızca owns_league() true ise o turnuva.
//
// JWT doğrulaması kapalı yayınlanır (`--no-verify-jwt`); yetki burada denetlenir.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { ACCOUNT_COLUMNS, type IgAccount, syncAccount } from "../_shared/instagram_sync.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
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

  const given = req.headers.get("x-sync-secret") ?? "";
  if (given) {
    const { data: s } = await admin
      .from("app_private_settings")
      .select("value")
      .eq("key", "instagram_sync_secret")
      .maybeSingle();
    if (!s?.value || s.value !== given) return json({ error: "Yetkisiz." }, 401);

    const soon = new Date(Date.now() + 10 * 24 * 3600_000).toISOString();
    const { data: accounts, error } = await admin
      .from("league_instagram_accounts")
      .select(ACCOUNT_COLUMNS)
      .or(`import_news.eq.true,expires_at.lt.${soon}`);
    if (error) return json({ error: error.message }, 500);
    const results = [];
    for (const a of (accounts ?? []) as IgAccount[]) results.push(await syncAccount(admin, a));
    return json({ results });
  }

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

  const { data: a } = await admin
    .from("league_instagram_accounts")
    .select(ACCOUNT_COLUMNS)
    .eq("league_id", leagueId)
    .maybeSingle();
  if (!a) return json({ error: "Instagram hesabı bağlı değil." }, 404);
  const r = await syncAccount(admin, a as IgAccount);
  return r.error ? json({ error: r.error }, 502) : json(r);
});
