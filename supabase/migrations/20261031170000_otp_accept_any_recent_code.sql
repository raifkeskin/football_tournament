-- Doğrulama kodu: süresi dolmamış, kullanılmamış kodlardan herhangi biri
-- kabul edilir (önceden yalnız en sonuncusu). Kişi birkaç kez kod isteyince
-- adminin Telegram'dan ilettiği önceki kod "hatalı" çıkıyordu. Kod
-- kullanılınca numaradaki diğer kodlar da geçersiz olur. Telegram mesajında
-- numara "0 0 (5xx)" yerine "0 (5xx)".

create or replace function public._otp_consume(p_raw text, p_code text)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  c public.sms_otp_codes%rowtype;
  m public.sms_otp_codes%rowtype;
  v_code text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
begin
  -- Süresi dolmamış, kullanılmamış kodlardan herhangi biri geçer: kişi
  -- birkaç kez kod isteyince elle iletilen önceki kod da çalışır.
  select * into c from public.sms_otp_codes
   where phone_raw10 = p_raw and used_at is null and expires_at >= now()
   order by created_at desc
   limit 1
   for update;
  if not found then
    return 'expired';
  end if;
  if c.attempts >= 5 then
    return 'too_many_attempts';
  end if;
  select * into m from public.sms_otp_codes
   where phone_raw10 = p_raw and used_at is null and expires_at >= now()
     and code_hash = extensions.crypt(v_code, code_hash)
   order by created_at desc
   limit 1;
  if not found then
    -- Yanlış deneme en yeni koda sayılır.
    update public.sms_otp_codes set attempts = attempts + 1 where id = c.id;
    return case when c.attempts + 1 >= 5 then 'too_many_attempts' else 'wrong_code' end;
  end if;
  -- Kullanılınca numaradaki diğer kodlar da geçersiz olur.
  update public.sms_otp_codes set used_at = now()
   where phone_raw10 = p_raw and used_at is null;
  return 'ok';
end;
$function$;

create or replace function public.register_otp_check(p_phone text, p_code text)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  c public.sms_otp_codes%rowtype;
  m public.sms_otp_codes%rowtype;
  v_code text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  -- Süresi dolmamış, kullanılmamış kodlardan herhangi biri geçer: kişi
  -- birkaç kez kod isteyince elle iletilen önceki kod da çalışır.
  select * into c from public.sms_otp_codes
   where phone_raw10 = v_raw and used_at is null and expires_at >= now()
   order by created_at desc
   limit 1
   for update;
  if not found then
    return 'expired';
  end if;
  if c.attempts >= 5 then
    return 'too_many_attempts';
  end if;
  select * into m from public.sms_otp_codes
   where phone_raw10 = v_raw and used_at is null and expires_at >= now()
     and code_hash = extensions.crypt(v_code, code_hash)
   order by created_at desc
   limit 1;
  if not found then
    -- Yanlış deneme en yeni koda sayılır.
    update public.sms_otp_codes set attempts = attempts + 1 where id = c.id;
    return case when c.attempts + 1 >= 5 then 'too_many_attempts' else 'wrong_code' end;
  end if;
  return 'ok';
end;
$function$;

CREATE OR REPLACE FUNCTION public._otp_issue(p_raw text, p_kind text, p_title text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_provider text;
  v_code text;
  v_key text;
  v_hash text;
  v_sender text;
  v_template text;
  v_request bigint;
  v_wa text;
begin
  if exists (
    select 1 from public.sms_otp_codes
     where phone_raw10 = p_raw and created_at > now() - interval '60 seconds'
  ) then
    return 'too_soon';
  end if;
  if (select count(*) from public.sms_otp_codes
       where phone_raw10 = p_raw
         and created_at > now() - interval '1 hour') >= 5 then
    return 'too_many';
  end if;

  select value #>> '{}' into v_provider
    from public.app_settings where key = 'sms_otp_provider';
  v_provider := coalesce(v_provider, 'telegram');

  v_code := lpad(
    ((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint)
      % 1000000)::text,
    6, '0');

  if v_provider = 'iletimerkezi' then
    select value into v_key from public.app_private_settings where key = 'iletimerkezi_key';
    select value into v_hash from public.app_private_settings where key = 'iletimerkezi_hash';
    select value into v_sender from public.app_private_settings where key = 'iletimerkezi_sender';
    select value into v_template from public.app_private_settings where key = 'sms_otp_template';
    v_template := coalesce(nullif(v_template, ''),
      'Doğrulama kodunuz: {kod}. Kodu kimseyle paylaşmayın.');
    if coalesce(v_key, '') = '' or coalesce(v_hash, '') = ''
       or coalesce(v_sender, '') = '' then
      return 'not_configured';
    end if;
    select net.http_post(
      url := 'https://api.iletimerkezi.com/v1/send-sms/json',
      body := jsonb_build_object('request', jsonb_build_object(
        'authentication', jsonb_build_object('key', v_key, 'hash', v_hash),
        'order', jsonb_build_object(
          'sender', v_sender,
          'sendDateTime', '',
          'iys', '0',
          'message', jsonb_build_object(
            'text', replace(v_template, '{kod}', v_code),
            'receipents', jsonb_build_object('number', jsonb_build_array(p_raw))
          )
        )
      )),
      headers := '{"Content-Type": "application/json"}'::jsonb
    ) into v_request;
  else
    -- Test modu: kod adminlere gider, admin WhatsApp'tan iletir.
    v_wa := 'https://wa.me/90' || p_raw
      || '?text=Lig%20Masas%C4%B1%20do%C4%9Frulama%20kodunuz%3A%20' || v_code;
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '📱 ' || p_title
        || E'\n' || public.format_phone_raw10(p_raw)
        || E'\nKod: ' || v_code,
      jsonb_build_array(jsonb_build_array(
        jsonb_build_object('text', 'WhatsApp ile gönder', 'url', v_wa)
      ))
    );
  end if;

  insert into public.sms_otp_codes (
    phone_raw10, kind, code_hash, provider, request_id, expires_at
  ) values (
    p_raw, p_kind, extensions.crypt(v_code, extensions.gen_salt('bf')),
    v_provider, v_request,
    -- Elle iletilen kod için daha uzun süre.
    now() + case when v_provider = 'iletimerkezi'
                 then interval '3 minutes' else interval '30 minutes' end
  );
  return 'sent';
end;
$function$;
