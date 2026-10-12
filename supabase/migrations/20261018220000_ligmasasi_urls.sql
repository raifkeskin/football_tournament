-- Telegram 'Siteyi Aç' düğmesi yeni adrese (masterfutbol.web.app → ligmasasi.com).
CREATE OR REPLACE FUNCTION public.telegram_notify(p_user_ids uuid[], p_text text, p_buttons jsonb DEFAULT NULL::jsonb, p_photo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_token text;
  v_chat bigint;
  v_markup jsonb;
begin
  select value into v_token from public.app_private_settings where key = 'telegram_bot_token';
  if coalesce(v_token, '') = '' then
    return;
  end if;

  v_markup := jsonb_build_object(
    'inline_keyboard',
    coalesce(p_buttons, '[]'::jsonb) || jsonb_build_array(jsonb_build_array(
      jsonb_build_object('text', 'Siteyi Aç', 'url', 'https://ligmasasi.com')
    ))
  );

  for v_chat in
    select distinct chat_id from public.telegram_links where user_id = any (p_user_ids)
  loop
    if coalesce(p_photo, '') <> '' then
      perform net.http_post(
        url := 'https://api.telegram.org/bot' || v_token || '/sendPhoto',
        body := jsonb_build_object('chat_id', v_chat, 'photo', p_photo,
                                   'caption', p_text, 'reply_markup', v_markup),
        headers := '{"Content-Type": "application/json"}'::jsonb
      );
    else
      perform net.http_post(
        url := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
        body := jsonb_build_object('chat_id', v_chat, 'text', p_text,
                                   'reply_markup', v_markup),
        headers := '{"Content-Type": "application/json"}'::jsonb
      );
    end if;
  end loop;
exception when others then
  raise warning 'telegram_notify: %', sqlerrm;
end;
$function$

;
