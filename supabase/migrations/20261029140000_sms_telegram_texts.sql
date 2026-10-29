-- SMS ve Telegram metinleri talep türüne göre ayrılır:
-- kayıt / şifre yenileme için ayrı SMS şablonu (app_private_settings
-- sms_otp_template_register / sms_otp_template_reset ile değiştirilebilir)
-- ve Telegram'da türü belirgin başlık.

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
        then 'Lig Masası şifre yenileme kodunuz: {kod}. 3 dakika geçerlidir, kimseyle paylaşmayın.'
        else 'Lig Masası kayıt kodunuz: {kod}. 3 dakika geçerlidir, kimseyle paylaşmayın.'
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

CREATE OR REPLACE FUNCTION public.account_requests_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_player text;
begin
  select nullif(trim(concat_ws(' ', p.name, p.surname)), '') into v_player
  from public.players p
  where public.phone_raw10(p.phone) = new.phone_raw10
  limit 1;

  perform public.telegram_notify(
    array(select user_id from public.admins where user_id is not null),
    case when new.kind = 'reset'
      then E'🔑 ŞİFRE YENİLEME talebi\nHesabı var, şifresini unuttu'
      else E'🆕 YENİ KAYIT talebi\nİlk kez hesap açılacak' end
      || E'\n\n' || coalesce(v_player, new.full_name, 'Oyuncu kaydı yok')
      || E'\n' || public.format_phone_raw10(new.phone_raw10),
    jsonb_build_array(jsonb_build_array(
      jsonb_build_object('text', '✅ Onayla', 'callback_data', 'acc_ok:' || new.id),
      jsonb_build_object('text', '❌ Reddet', 'callback_data', 'acc_no:' || new.id)
    ))
  );
  return new;
end;
$function$;
