-- Doğrulama SMS metinleri: kayıt türü açıkça yazılır, 'geçici' kalktı.
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
  v_tur text;
  v_request bigint;
  v_id uuid;
  v_ip text;
  v_today int;
begin
  if exists (
    select 1 from public.sms_otp_codes
     where phone_raw10 = p_raw and created_at > now() - interval '60 seconds'
  ) then
    return 'too_soon';
  end if;
  -- Aynı numaraya saatte en çok 3, günde en çok 5 kod.
  if (select count(*) from public.sms_otp_codes
       where phone_raw10 = p_raw
         and created_at > now() - interval '1 hour') >= 3
     or (select count(*) from public.sms_otp_codes
          where phone_raw10 = p_raw
            and created_at > now() - interval '24 hours') >= 5 then
    return 'too_many';
  end if;
  -- Gün içinde 10 yanlış kod girilen numara 24 saat kilitli.
  if (select coalesce(sum(attempts), 0) from public.sms_otp_codes
       where phone_raw10 = p_raw
         and created_at > now() - interval '24 hours') >= 10 then
    return 'too_many';
  end if;
  -- Aynı bağlantıdan (IP) saatte en çok 10 farklı numara.
  v_ip := nullif(btrim(split_part(
    coalesce(current_setting('request.headers', true), '{}')::json
      ->> 'x-forwarded-for', ',', 1)), '');
  if v_ip is not null and (
       select count(distinct phone_raw10) from public.sms_otp_codes
        where client_ip = v_ip and phone_raw10 <> p_raw
          and created_at > now() - interval '1 hour') >= 10 then
    return 'too_many';
  end if;
  -- Sistem geneli: günde en çok 300 kod; 240'ta (%80) adminlere uyarı.
  select count(*) into v_today from public.sms_otp_codes
   where created_at > now() - interval '24 hours';
  if v_today >= 300 then
    return 'too_many';
  end if;
  if v_today = 240 then
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '⚠️ Doğrulama kodu günlük sınırın %80''ine ulaştı (240 / 300). '
        || 'Olağandışı bir yoğunluk ya da kötüye kullanım olabilir.'
    );
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
    v_tur := case
      when p_kind = 'password_change' then 'şifre değiştirme için'
      when p_title ilike 'Futbolcu%' then 'Futbolcu kaydınız için'
      when p_title ilike 'Turnuva sorumlusu%' then 'Sorumlu kaydınız için'
      when p_title ilike '%taraftar%' then 'Taraftar kaydınız için'
      else 'kaydınız için' end;
    v_template := coalesce(nullif(v_template, ''),
      'Lig Masası {tur} doğrulama kodunuz: {kod}. Kodu kimseyle paylaşmayın.');
    v_template := replace(v_template, '{tur}', v_tur);
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
  end if;

  insert into public.sms_otp_codes (
    phone_raw10, kind, code_hash, provider, request_id, expires_at, client_ip
  ) values (
    p_raw, p_kind, extensions.crypt(v_code, extensions.gen_salt('bf')),
    v_provider, v_request,
    -- Elle iletilen kod için daha uzun süre.
    now() + case when v_provider = 'iletimerkezi'
                 then interval '3 minutes' else interval '30 minutes' end,
    v_ip
  ) returning id into v_id;

  if v_provider <> 'iletimerkezi' then
    -- Test modu: kod adminlere gider, admin WhatsApp'tan iletir. Aynı
    -- numaranın önceki kodu için hatırlatma durur.
    update public.otp_telegram_reminders
       set done_at = now(), code = null
     where phone_raw10 = p_raw and done_at is null;
    insert into public.otp_telegram_reminders (otp_id, phone_raw10, title, code)
    values (v_id, p_raw, p_title, v_code);
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '📱 ' || p_title
        || E'\n' || public.format_phone_raw10(p_raw)
        || E'\nKod: ' || v_code,
      public._otp_telegram_buttons(v_id, p_raw, v_code)
    );
  end if;
  return 'sent';
end;
$function$;

CREATE OR REPLACE FUNCTION public.sms_otp_send(p_phone text, p_reset boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_has_account boolean;
  v_kind text;
  v_code text;
  v_provider text;
  v_key text;
  v_hash text;
  v_sender text;
  v_template text;
  v_request bigint;
begin
  if not public.sms_otp_enabled() then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;

  select exists (
    select 1 from auth.users where email = v_raw || '@masterclass.com'
  ) into v_has_account;

  if p_reset and not v_has_account and not exists (
    select 1 from public.players p where public.phone_raw10(p.phone) = v_raw
  ) then
    return 'not_registered';
  end if;
  -- Kayıt yalnızca oyuncu kaydında bulunan numaralara açık
  -- (request_account_password ile aynı kural).
  if not v_has_account and not exists (
    select 1 from public.players p where public.phone_raw10(p.phone) = v_raw
  ) then
    return 'unknown_phone';
  end if;

  -- Aynı numaraya 60 sn'de bir, saatte en fazla 5 kod.
  if exists (
    select 1 from public.sms_otp_codes
    where phone_raw10 = v_raw and created_at > now() - interval '60 seconds'
  ) then
    return 'too_soon';
  end if;
  if (select count(*) from public.sms_otp_codes
      where phone_raw10 = v_raw and created_at > now() - interval '1 hour') >= 5 then
    return 'too_many';
  end if;

  select value #>> '{}' into v_provider
  from public.app_settings where key = 'sms_otp_provider';
  v_provider := coalesce(v_provider, 'telegram');

  v_kind := case when v_has_account then 'reset' else 'register' end;
  v_code := lpad(
    ((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint)
      % 1000000)::text,
    6, '0');

  if v_provider = 'iletimerkezi' then
    select value into v_key from public.app_private_settings where key = 'iletimerkezi_key';
    select value into v_hash from public.app_private_settings where key = 'iletimerkezi_hash';
    select value into v_sender from public.app_private_settings where key = 'iletimerkezi_sender';
    select value into v_template from public.app_private_settings
    where key = 'sms_otp_template_' || v_kind;
    v_template := coalesce(nullif(v_template, ''),
      case when v_kind = 'reset'
        then 'Lig Masası şifre yenileme için doğrulama kodunuz: {kod}. Kodu kimseyle paylaşmayın.'
        else 'Lig Masası Futbolcu kaydınız için doğrulama kodunuz: {kod}. Kodu kimseyle paylaşmayın.'
      end);
    if coalesce(v_key, '') = '' or coalesce(v_hash, '') = '' or coalesce(v_sender, '') = '' then
      return 'not_configured';
    end if;

    -- iys=0: doğrulama kodu ticari ileti değildir (İYS onayı aranmaz).
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
            'receipents', jsonb_build_object('number', jsonb_build_array(v_raw))
          )
        )
      )),
      headers := '{"Content-Type": "application/json"}'::jsonb
    ) into v_request;
  else
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      case when v_kind = 'reset'
        then '📱 SMS test kodu · ŞİFRE YENİLEME (hesabı var)'
        else '📱 SMS test kodu · YENİ KAYIT (ilk hesap)' end
        || E'\n' || public.format_phone_raw10(v_raw)
        || E'\nKod: ' || v_code
    );
  end if;

  insert into public.sms_otp_codes (
    phone_raw10, kind, code_hash, provider, request_id, expires_at
  ) values (
    v_raw, v_kind, extensions.crypt(v_code, extensions.gen_salt('bf')),
    v_provider, v_request, now() + interval '3 minutes'
  );

  return case when v_has_account then 'sent_reset' else 'sent' end;
end;
$function$;
