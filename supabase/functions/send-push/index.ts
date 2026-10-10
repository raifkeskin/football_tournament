// Telefon bildirimi gönderimi. Veritabanındaki push_send() tarafından
// çağrılır; yalnızca `x-push-secret` başlığı doğru olan istekler işlenir.
//  - Web (tarayıcı) abonelikleri: Web Push (VAPID).
//  - Uygulama (APK) abonelikleri: adresi `fcm:<belirteç>` olanlar, Firebase
//    Cloud Messaging HTTP v1 ile.
// Süresi dolmuş / iptal edilmiş abonelikler silinir.
//
// Gizli değerler (supabase secrets): VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY,
// VAPID_SUBJECT, PUSH_SECRET, FCM_SERVICE_ACCOUNT (Firebase hizmet hesabı
// JSON'u). PUSH_SECRET, app_private_settings.push_secret ile aynıdır.

import webpush from "npm:web-push@3.6.7";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

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

// --- FCM ---------------------------------------------------------------------

type ServiceAccount = { project_id: string; client_email: string; private_key: string };
let fcmAccount: ServiceAccount | null = null;
try {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (raw) fcmAccount = JSON.parse(raw) as ServiceAccount;
} catch (e) {
  console.error("FCM_SERVICE_ACCOUNT okunamadı", (e as Error).message);
}
let fcmToken: { value: string; exp: number } | null = null;

async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (fcmToken && fcmToken.exp - 60 > now) return fcmToken.value;
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`oauth ${res.status} ${await res.text()}`);
  const j = await res.json();
  fcmToken = { value: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return fcmToken.value;
}

/// true: gönderildi; false: belirteç geçersiz (silinmeli). Diğer hatalar
/// fırlatılır.
async function sendFcm(
  sa: ServiceAccount,
  token: string,
  p: { title: string; body: string; url: string; tag?: string },
): Promise<boolean> {
  const access = await fcmAccessToken(sa);
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: p.title, body: p.body },
          data: { url: p.url, tag: p.tag ?? "" },
          android: {
            priority: "high",
            ttl: "86400s",
            notification: { tag: p.tag ?? undefined, sound: "default" },
          },
        },
      }),
    },
  );
  if (res.ok) return true;
  const text = await res.text();
  if (res.status === 404 || /UNREGISTERED|registration-token-not-registered/i.test(text)) {
    return false;
  }
  if (res.status === 400 && /INVALID_ARGUMENT/.test(text) && /token/i.test(text)) {
    return false;
  }
  throw new Error(`fcm ${res.status} ${text}`);
}

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
      if (s.endpoint.startsWith("fcm:")) {
        if (!fcmAccount) return;
        try {
          const ok = await sendFcm(fcmAccount, s.endpoint.slice(4), {
            title: p.title,
            body: p.body ?? "",
            url: p.url ?? "/",
            tag: p.tag,
          });
          if (ok) sent++;
          else dead.push(s.id);
        } catch (e) {
          console.error("fcm failed", (e as Error).message);
        }
        return;
      }
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
