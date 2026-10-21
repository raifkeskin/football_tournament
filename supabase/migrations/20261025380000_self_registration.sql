-- Yeni Kayıt Ol akışı: Futbolcu Profili (kimlik çipiyle) ya da Turnuva
-- Kurucu / Sorumlusu (ad, soyad, telefon). Telefon doğrulama kodu
-- sms_otp_provider'a göre gider: 'telegram' → adminlerin Telegram'ına
-- (WhatsApp ile gönder butonuyla), 'iletimerkezi' → SMS.
-- app_settings.self_registration_enabled kapalıyken eski kayıt akışı kalır.

insert into public.app_settings (key, value)
values ('self_registration_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.self_registration_enabled()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    (select value = 'true'::jsonb from public.app_settings
      where key = 'self_registration_enabled'),
    false)
$function$;

-- Kod üretir ve gönderir. Dönüş: sent | too_soon | too_many | not_configured.
create or replace function public._otp_issue(
  p_raw text, p_kind text, p_title text
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
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
        || E'\n0 ' || public.format_phone_raw10(p_raw)
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
revoke all on function public._otp_issue(text, text, text) from public, anon, authenticated;

-- Kodu denetler ve kullanır. Dönüş: ok | expired | too_many_attempts | wrong_code.
create or replace function public._otp_consume(p_raw text, p_code text)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c public.sms_otp_codes%rowtype;
  v_code text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
begin
  select * into c from public.sms_otp_codes
   where phone_raw10 = p_raw and used_at is null
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
  return 'ok';
end;
$function$;
revoke all on function public._otp_consume(text, text) from public, anon, authenticated;

-- 1. adım: telefon doğrulama kodu. p_kind: player | organizer.
-- Dönüş: disabled | invalid_phone | has_account | sent | too_soon |
-- too_many | not_configured.
create or replace function public.register_otp_send(
  p_phone text, p_kind text, p_name text default null
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_raw text := public.phone_raw10(p_phone);
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if exists (select 1 from auth.users where email = v_raw || '@masterclass.com') then
    return 'has_account';
  end if;
  return public._otp_issue(
    v_raw, 'register',
    case when p_kind = 'player' then 'Futbolcu kaydı' else 'Turnuva sorumlusu kaydı' end
      || coalesce(' · ' || nullif(left(btrim(p_name), 60), ''), '')
  );
end;
$function$;
revoke all on function public.register_otp_send(text, text, text) from public;
grant execute on function public.register_otp_send(text, text, text) to anon, authenticated;

-- Turnuva kurucu / sorumlusu: kod + ad soyad + şifre → hesap.
-- Dönüş: ok | disabled | invalid_phone | invalid_name | weak_password |
-- has_account | expired | too_many_attempts | wrong_code.
create or replace function public.register_organizer(
  p_phone text, p_code text, p_password text, p_first text, p_last text
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_name text := btrim(concat_ws(' ', btrim(p_first), btrim(p_last)));
  v_res text;
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if length(btrim(coalesce(p_first, ''))) < 2
     or length(btrim(coalesce(p_last, ''))) < 2 or length(v_name) > 80 then
    return 'invalid_name';
  end if;
  if p_password is null or length(p_password) not between 6 and 10
     or p_password !~ '[^A-Za-z]' then
    return 'weak_password';
  end if;
  if exists (select 1 from auth.users where email = v_raw || '@masterclass.com') then
    return 'has_account';
  end if;

  v_res := public._otp_consume(v_raw, p_code);
  if v_res <> 'ok' then
    return v_res;
  end if;

  perform public.set_phone_account_password(v_raw, p_password, false, v_name);
  return 'ok';
end;
$function$;
revoke all on function public.register_organizer(text, text, text, text, text) from public;
grant execute on function public.register_organizer(text, text, text, text, text) to anon, authenticated;

-- Futbolcu: kimlik çipinden ad, soyad, doğum tarihi, TC + kod + kişisel
-- bilgiler → hesap + onaylı profil. Aynı kişi zaten kayıtlıysa (aynı TC
-- onaylı ya da ad, soyad, doğum tarihi tutan tek profil) yeni profil
-- açılmaz, o profil hesaba bağlanır.
-- Dönüş: ok | disabled | invalid_phone | invalid_tc | invalid_data |
-- weak_password | has_account | profile_has_account | ambiguous |
-- expired | too_many_attempts | wrong_code.
create or replace function public.register_player(
  p_phone text, p_code text, p_password text,
  p_first text, p_last text, p_birth date, p_tc text,
  p_main text, p_sub text, p_foot text, p_height int, p_weight int
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_first text := btrim(coalesce(p_first, ''));
  v_last text := btrim(coalesce(p_last, ''));
  v_hash text;
  v_player uuid;
  v_auth uuid;
  v_count int;
  v_uid uuid;
  v_res text;
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if not public.tc_valid(p_tc) then
    return 'invalid_tc';
  end if;
  if length(v_first) < 2 or length(v_last) < 2
     or p_birth is null or p_birth < date '1940-01-01'
     or p_birth > (current_date - interval '10 years')::date
     or coalesce(p_main, '') not in ('Kaleci', 'Defans', 'Orta Saha', 'Forvet')
     or (p_sub is not null and p_sub not in ('Kaleci', 'Stoper', 'Bek',
         'Defansif', 'Merkez', 'Ofansif', 'Kanat', 'Santrfor', 'Kanat Forvet'))
     or (p_foot is not null and p_foot not in ('Sağ', 'Sol', 'Her İkisi'))
     or (p_height is not null and p_height not between 120 and 230)
     or (p_weight is not null and p_weight not between 35 and 200) then
    return 'invalid_data';
  end if;
  if p_password is null or length(p_password) not between 6 and 10
     or p_password !~ '[^A-Za-z]' then
    return 'weak_password';
  end if;
  if exists (select 1 from auth.users where email = v_raw || '@masterclass.com') then
    return 'has_account';
  end if;

  v_hash := public._identity_hash(p_tc);

  -- Aynı kişi: önce TC onayı, yoksa ad + soyad + doğum tarihi tutan
  -- onaysız profil.
  select v.player_id, p.auth_uid into v_player, v_auth
    from public.player_verifications v
    join public.players p on p.id = v.player_id
   where v.tc_hash = v_hash;
  if v_player is null then
    select count(*), min(p.id::text)::uuid into v_count, v_player
      from public.players p
     where p.birth_date = p_birth
       and public.tr_fold(p.surname) = public.tr_fold(v_last)
       and (public.tr_fold(p.name) = public.tr_fold(v_first)
            or public.tr_fold(v_first) like public.tr_fold(p.name) || ' %'
            or public.tr_fold(p.name) like public.tr_fold(v_first) || ' %')
       and not exists (select 1 from public.player_verifications v
                        where v.player_id = p.id);
    if v_count > 1 then
      return 'ambiguous';
    end if;
    if v_player is not null then
      select auth_uid into v_auth from public.players where id = v_player;
    end if;
  end if;
  if v_auth is not null then
    return 'profile_has_account';
  end if;

  v_res := public._otp_consume(v_raw, p_code);
  if v_res <> 'ok' then
    return v_res;
  end if;

  if v_player is null then
    insert into public.players (
      name, surname, birth_date, phone, main_position, sub_position,
      preferred_foot, height, weight
    ) values (
      v_first, v_last, p_birth, v_raw, p_main, p_sub, p_foot, p_height, p_weight
    ) returning id into v_player;
  else
    -- Mevcut profil: kişinin kendi girdikleri yazılır; ad ve doğum
    -- tarihi profildeki gibi kalır.
    update public.players
       set phone = v_raw,
           main_position = p_main,
           sub_position = coalesce(p_sub, sub_position),
           preferred_foot = coalesce(p_foot, preferred_foot),
           height = coalesce(p_height, height),
           weight = coalesce(p_weight, weight)
     where id = v_player;
  end if;

  v_uid := public.set_phone_account_password(
    v_raw, p_password, false, v_first || ' ' || v_last);

  -- Hesap açılırken aynı numaralı başka bir kayıt bağlandıysa düzeltilir.
  update public.players set auth_uid = null
   where auth_uid = v_uid and id <> v_player;
  update public.players set auth_uid = v_uid where id = v_player;

  insert into public.player_verifications (player_id, tc_hash, verified_by)
  values (v_player, v_hash, v_uid)
  on conflict (player_id) do nothing;
  insert into public.identity_events (player_id, action, user_id)
  values (v_player, 'register', v_uid);

  return 'ok';
end;
$function$;
revoke all on function public.register_player(text, text, text, text, text, date, text, text, text, text, int, int) from public;
grant execute on function public.register_player(text, text, text, text, text, date, text, text, text, text, int, int) to anon, authenticated;

-- Kodu kullanmadan denetler (ekranda "Doğrula" adımı); yanlış deneme sayılır.
-- Dönüş: ok | disabled | expired | too_many_attempts | wrong_code.
create or replace function public.register_otp_check(p_phone text, p_code text)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  c public.sms_otp_codes%rowtype;
  v_code text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
begin
  if not public.self_registration_enabled() then
    return 'disabled';
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
  return 'ok';
end;
$function$;
revoke all on function public.register_otp_check(text, text) from public;
grant execute on function public.register_otp_check(text, text) to anon, authenticated;
