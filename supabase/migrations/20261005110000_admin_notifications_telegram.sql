-- Admin bildirimleri ntfy yerine Telegram botuyla (ntfy'nin ücretsiz kotası
-- Supabase'in ortak çıkış IP'si yüzünden sürekli doluyordu).
--
-- Ayarlar git dışında, app_private_settings tablosunda:
--   'telegram_bot_token'  BotFather'ın verdiği anahtar
--   'telegram_chat_id'    bildirimin gideceği sohbet (kişi ya da grup)
-- Ayar yoksa bildirim gönderilmez; hata talebi asla engellemez.

create or replace function public.notify_admin(p_title text, p_message text, p_tags text default null)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_token text;
  v_chat text;
  v_icon text;
begin
  select value into v_token from public.app_private_settings where key = 'telegram_bot_token';
  select value into v_chat from public.app_private_settings where key = 'telegram_chat_id';
  if coalesce(v_token, '') = '' or coalesce(v_chat, '') = '' then
    return;
  end if;

  v_icon := case p_tags
    when 'key' then '🔑 '
    when 'bust_in_silhouette' then '👤 '
    when 'white_check_mark' then '✅ '
    else '' end;

  perform net.http_post(
    url := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
    body := jsonb_build_object(
      'chat_id', v_chat,
      'text', v_icon || p_title || E'\n' || p_message,
      'reply_markup', jsonb_build_object(
        'inline_keyboard', jsonb_build_array(jsonb_build_array(
          jsonb_build_object('text', 'Siteyi Aç', 'url', 'https://masterfutbol.web.app')
        ))
      )
    ),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
exception when others then
  raise warning 'notify_admin: %', sqlerrm;
end;
$$;

revoke all on function public.notify_admin(text, text, text) from public;
