-- SMS ile doğrulama (Kayıt Ol / Şifremi Unuttum).
--
-- app_settings.sms_otp_enabled kapalıyken (varsayılan) eski akış sürer:
-- talep → Telegram → admin onayı → geçici şifre WhatsApp'tan.
-- Açıkken kullanıcı telefonuna gelen 6 haneli kodu girip kendi şifresini
-- belirler; admin onayı gerekmez.
--
-- app_settings.sms_otp_provider:
--   'telegram'     → test modu: kod SMS yerine adminlerin Telegram'ına gider.
--   'iletimerkezi' → gerçek SMS. Bilgiler git'e girmez, app_private_settings'e
--                    psql ile yazılır:
--     insert into public.app_private_settings (key, value) values
--       ('iletimerkezi_key', '<API Key>'),
--       ('iletimerkezi_hash', '<API Hash>'),
--       ('iletimerkezi_sender', '<onaylı başlık>'),
--       ('sms_otp_template', 'Doğrulama kodunuz: {kod}. ...')  -- isteğe bağlı
--     on conflict (key) do update set value = excluded.value, updated_at = now();
-- Gönderim sonuçları sms_otp_codes.request_id → net._http_response'tan
-- izlenebilir.

insert into public.app_settings (key, value) values
  ('sms_otp_enabled', 'false'::jsonb),
  ('sms_otp_provider', '"telegram"'::jsonb)
on conflict (key) do nothing;

create table if not exists public.sms_otp_codes (
  id          uuid primary key default gen_random_uuid(),
  phone_raw10 text not null,
  kind        text not null check (kind in ('register', 'reset')),
  code_hash   text not null,
  attempts    int not null default 0,
  provider    text not null,
  request_id  bigint,
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists sms_otp_codes_phone_idx
  on public.sms_otp_codes (phone_raw10, created_at desc);

-- İstemciden erişilemez; yalnızca aşağıdaki security definer fonksiyonlar.
alter table public.sms_otp_codes enable row level security;
revoke all on public.sms_otp_codes from anon, authenticated;

create or replace function public.sms_otp_enabled()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(
    (select value = 'true'::jsonb from public.app_settings
     where key = 'sms_otp_enabled'),
    false
  )
$$;

grant execute on function public.sms_otp_enabled() to anon, authenticated;

-- Telefon hesabını açar ya da şifresini değiştirir (approve_account_request
-- ile aynı hesap yapısı: <telefon>@masterclass.com). Hesap id'sini döner.
create or replace function public.set_phone_account_password(
  p_raw10 text,
  p_password text,
  p_must_change boolean,
  p_name text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text := p_raw10 || '@masterclass.com';
  v_uid uuid;
  v_phone text;
  v_name text;
begin
  select id into v_uid from auth.users where email = v_email;

  if v_uid is null then
    select coalesce(
             nullif(trim(coalesce(p_name, '')), ''),
             (select nullif(trim(concat_ws(' ', pl.name, pl.surname)), '')
              from public.players pl
              where public.phone_raw10(pl.phone) = p_raw10
              limit 1)
           )
    into v_name;

    v_uid := gen_random_uuid();
    -- Telefon başka bir hesapta kayıtlıysa (users_phone_key) boş bırakılır.
    v_phone := '90' || p_raw10;
    if exists (select 1 from auth.users where phone = v_phone) then
      v_phone := null;
    end if;

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, phone, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated',
      'authenticated', v_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')),
      now(), v_phone,
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      jsonb_strip_nulls(jsonb_build_object(
        'email_verified', true,
        'must_change_password', p_must_change,
        'name', v_name
      )),
      now(), now(), '', '', '', ''
    );

    insert into auth.identities (
      provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      v_uid::text, v_uid,
      jsonb_build_object(
        'sub', v_uid::text, 'email', v_email,
        'email_verified', false, 'phone_verified', false
      ),
      'email', now(), now(), now()
    );

    if v_name is not null then
      insert into public.app_users (phone, name, auth_uid, role)
      values (p_raw10, v_name, v_uid::text, 'player')
      on conflict (phone) do update
        set auth_uid = excluded.auth_uid,
            name = coalesce(public.app_users.name, excluded.name);
    end if;
  else
    update auth.users
    set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          || jsonb_build_object('must_change_password', p_must_change),
        updated_at = now()
    where id = v_uid;

    -- Eski şifreyle açık oturumlar kapanır.
    delete from auth.sessions where user_id = v_uid;
  end if;

  return v_uid;
end;
$$;

revoke all on function public.set_phone_account_password(text, text, boolean, text) from public, anon, authenticated;

-- Kod gönderir. Sonuç: 'sent' | 'sent_reset' | 'disabled' | 'invalid_phone'
-- | 'not_registered' | 'unknown_phone' | 'too_soon' | 'too_many' | 'not_configured'.
create or replace function public.sms_otp_send(
  p_phone text,
  p_reset boolean default false
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
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

  if p_reset and not v_has_account then
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
    select value into v_template from public.app_private_settings where key = 'sms_otp_template';
    v_template := coalesce(nullif(v_template, ''),
      'Doğrulama kodunuz: {kod}. Kodu kimseyle paylaşmayın.');
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
      '📱 SMS test kodu'
        || case when v_kind = 'reset' then ' (şifre sıfırlama)' else ' (kayıt)' end
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
$$;

grant execute on function public.sms_otp_send(text, boolean) to anon, authenticated;

-- Kodu doğrular ve şifreyi belirler. Sonuç: 'ok' | 'disabled' | 'invalid_phone'
-- | 'weak_password' | 'expired' | 'wrong_code' | 'too_many_attempts'.
create or replace function public.sms_otp_verify(
  p_phone text,
  p_code text,
  p_password text
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_code text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
  c public.sms_otp_codes%rowtype;
  v_uid uuid;
begin
  if not public.sms_otp_enabled() then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if p_password is null or length(p_password) not between 6 and 10
     or p_password !~ '[^A-Za-z]' then
    return 'weak_password';
  end if;

  select * into c from public.sms_otp_codes
  where phone_raw10 = v_raw and used_at is null
  order by created_at desc
  limit 1
  for update;

  if not found or c.expires_at < now() then
    return 'expired';
  end if;
  if c.attempts >= 5 then
    return 'too_many_attempts';
  end if;
  if c.code_hash <> extensions.crypt(v_code, c.code_hash) then
    update public.sms_otp_codes set attempts = attempts + 1 where id = c.id;
    return case when c.attempts + 1 >= 5 then 'too_many_attempts' else 'wrong_code' end;
  end if;

  update public.sms_otp_codes set used_at = now() where id = c.id;

  v_uid := public.set_phone_account_password(v_raw, p_password, false);

  -- Bu numaranın eski akıştan kalan bekleyen talepleri kapanır.
  update public.account_requests
  set status = 'approved', user_id = v_uid, reviewed_at = now()
  where phone_raw10 = v_raw and status = 'pending';

  return 'ok';
end;
$$;

grant execute on function public.sms_otp_verify(text, text, text) to anon, authenticated;

-- 1 günden eski kodlar silinir.
select cron.schedule(
  'sms-otp-cleanup',
  '17 4 * * *',
  $$delete from public.sms_otp_codes where created_at < now() - interval '1 day'$$
);
