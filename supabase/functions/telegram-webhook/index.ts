// Telegram bot webhook'u: bildirimlerdeki Onayla / Reddet butonları.
//
// Telegram her istekte `X-Telegram-Bot-Api-Secret-Token` başlığını gönderir;
// yalnızca bizim belirlediğimiz değerle gelen istekler işlenir. Karar,
// veritabanındaki telegram_act() ile ve butona basan sohbetin bağlı olduğu
// kullanıcının yetkisiyle verilir.
//
// Gizli değerler (supabase secrets): TELEGRAM_BOT_TOKEN,
// TELEGRAM_WEBHOOK_SECRET. SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY
// Supabase tarafından sağlanır.

import { createClient } from "jsr:@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const LOGIN_URL = "https://masterfutbol.web.app";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function telegram(method: string, body: Record<string, unknown>) {
  return fetch(`https://api.telegram.org/bot${BOT_TOKEN}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function formatPhone(raw10: string) {
  return `0 (${raw10.slice(0, 3)}) ${raw10.slice(3, 6)} ${raw10.slice(6, 8)} ${raw10.slice(8)}`;
}

/** Depodaki talep fotoğrafını siler (link bizim bucket'ımızdaysa). */
async function deletePhoto(url: unknown) {
  if (typeof url !== "string") return;
  const marker = "/storage/v1/object/public/media/";
  const i = url.indexOf(marker);
  if (i < 0) return;
  const path = decodeURIComponent(url.slice(i + marker.length).split("?")[0]);
  if (!path.startsWith("profile_requests/")) return;
  await supabase.storage.from("media").remove([path]);
}

Deno.serve(async (req) => {
  if (req.headers.get("x-telegram-bot-api-secret-token") !== WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  const update = await req.json().catch(() => ({}));
  const cq = update.callback_query;
  if (!cq) return new Response("ok");

  const [action, id] = String(cq.data ?? "").split(":");
  const msg = cq.message ?? {};
  const chatId = msg.chat?.id;
  const isPhoto = Array.isArray(msg.photo);
  const original: string = (isPhoto ? msg.caption : msg.text) ?? "";

  const { data, error } = await supabase.rpc("telegram_act", {
    p_chat_id: chatId,
    p_action: action,
    p_id: id,
  });

  if (error) {
    await telegram("answerCallbackQuery", {
      callback_query_id: cq.id,
      text: error.message,
      show_alert: true,
    });
    return new Response("ok");
  }

  const result = (data ?? {}) as Record<string, unknown>;
  const approved = result.status === "approved";
  let footer = approved ? "✅ Onaylandı" : "❌ Reddedildi";
  const buttons: unknown[][] = [];

  if (action === "acc_ok" && approved) {
    const phone = String(result.phone ?? "");
    const password = String(result.password ?? "");
    const text =
      `Lig Masası uygulamasına giriş için geçici şifreniz: ${password}\n\n` +
      `Giriş: ${LOGIN_URL}\n` +
      "İlk girişte kendi şifrenizi belirlemeniz istenecek.";
    footer += `\nGeçici şifre: ${password}`;
    buttons.push([
      {
        text: "📲 WhatsApp ile Gönder",
        url: `https://wa.me/90${phone}?text=${encodeURIComponent(text)}`,
      },
    ]);
    footer += `\n${formatPhone(phone)}`;
  }

  await deletePhoto(result.delete_photo);

  const newText = `${original}\n\n${footer}`;
  const markup = { inline_keyboard: buttons };
  if (isPhoto) {
    await telegram("editMessageCaption", {
      chat_id: chatId,
      message_id: msg.message_id,
      caption: newText,
      reply_markup: markup,
    });
  } else {
    await telegram("editMessageText", {
      chat_id: chatId,
      message_id: msg.message_id,
      text: newText,
      reply_markup: markup,
    });
  }
  await telegram("answerCallbackQuery", {
    callback_query_id: cq.id,
    text: approved ? "Onaylandı" : "Reddedildi",
  });
  return new Response("ok");
});
