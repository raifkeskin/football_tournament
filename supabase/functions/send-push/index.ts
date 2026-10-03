// Web Push gönderimi (Firebase'siz, VAPID). Veritabanındaki push_send()
// tarafından çağrılır; yalnızca `x-push-secret` başlığı doğru olan istekler
// işlenir. Süresi dolmuş / iptal edilmiş abonelikler (404, 410) silinir.
//
// Gizli değerler (supabase secrets): VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY,
// VAPID_SUBJECT, PUSH_SECRET. PUSH_SECRET, app_private_settings.push_secret
// ile aynıdır.

import webpush from "npm:web-push@3.6.7";
import { createClient } from "jsr:@supabase/supabase-js@2";

const PUSH_SECRET = Deno.env.get("PUSH_SECRET") ?? "";

webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "https://masterfutbol.web.app",
  Deno.env.get("VAPID_PUBLIC_KEY") ?? "",
  Deno.env.get("VAPID_PRIVATE_KEY") ?? "",
);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

type Payload = {
  user_ids: string[];
  title: string;
  body?: string;
  url?: string;
  tag?: string;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  if (!PUSH_SECRET || req.headers.get("x-push-secret") !== PUSH_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  const p = (await req.json()) as Payload;
  const ids = (p.user_ids ?? []).filter(Boolean);
  if (ids.length === 0 || !p.title) {
    return Response.json({ sent: 0, removed: 0 });
  }

  const { data: subs, error } = await supabase
    .from("push_subscriptions")
    .select("id, endpoint, p256dh, auth")
    .in("user_id", ids);
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const message = JSON.stringify({
    title: p.title,
    body: p.body ?? "",
    url: p.url ?? "/",
    tag: p.tag ?? undefined,
  });

  let sent = 0;
  const dead: string[] = [];
  await Promise.all(
    (subs ?? []).map(async (s) => {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          message,
          { TTL: 60 * 60 * 24, urgency: "high" },
        );
        sent++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        if (code === 404 || code === 410) dead.push(s.id);
        else console.error("push failed", code, (e as Error).message);
      }
    }),
  );
  if (dead.length) {
    await supabase.from("push_subscriptions").delete().in("id", dead);
  }
  return Response.json({ sent, removed: dead.length });
});
