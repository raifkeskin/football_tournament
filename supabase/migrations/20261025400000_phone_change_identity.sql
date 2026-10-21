-- Onaylı profil telefonunu kimliğini yeniden okutarak değiştirir: çipteki
-- TC, profilin onayındaki özetle tutmalı; yeni numaraya kod gider.
-- Kimlik doğrulama açık olanlara (identity_allowed) açık.

alter table public.sms_otp_codes drop constraint if exists sms_otp_codes_kind_check;
alter table public.sms_otp_codes add constraint sms_otp_codes_kind_check
  check (kind = any (array['register', 'reset', 'phone_change']));

-- Ortak denetim. Dönüş: ok | disabled | not_verified | identity_mismatch |
-- invalid_phone | same_phone | has_account.
create or replace function public._phone_change_guard(p_tc text, p_raw text)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_hash text;
begin
  if v_uid is null or not public.identity_allowed() then
    return 'disabled';
  end if;
  select v.tc_hash into v_hash
    from public.players p
    join public.player_verifications v on v.player_id = p.id
   where p.auth_uid = v_uid
   limit 1;
  if v_hash is null then
    return 'not_verified';
  end if;
  if not public.tc_valid(p_tc) or v_hash <> public._identity_hash(p_tc) then
    return 'identity_mismatch';
  end if;
  if p_raw is null or p_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if exists (select 1 from auth.users
              where id = v_uid and email = p_raw || '@masterclass.com') then
    return 'same_phone';
  end if;
  if exists (select 1 from auth.users where email = p_raw || '@masterclass.com') then
    return 'has_account';
  end if;
  return 'ok';
end;
$function$;
revoke all on function public._phone_change_guard(text, text) from public, anon, authenticated;

-- Kimlik okununca: bu kimlik hesabın onaylı profiline mi ait.
create or replace function public.phone_change_identity(p_tc text)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_res text := public._phone_change_guard(p_tc, '5000000000');
begin
  insert into public.identity_events (action, user_id)
  values ('phone_change_check', auth.uid());
  -- Sahte numarayla denetlendi: telefon sonuçları kimlik için önemsiz.
  return case when v_res in ('disabled', 'not_verified', 'identity_mismatch')
              then v_res else 'ok' end;
end;
$function$;
revoke all on function public.phone_change_identity(text) from public, anon;
grant execute on function public.phone_change_identity(text) to authenticated;

create or replace function public.phone_change_send(p_tc text, p_new_phone text)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_raw text := public.phone_raw10(p_new_phone);
  v_res text := public._phone_change_guard(p_tc, v_raw);
  v_name text;
begin
  if v_res <> 'ok' then
    return v_res;
  end if;
  select btrim(concat_ws(' ', name, surname)) into v_name
    from public.players where auth_uid = auth.uid() limit 1;
  return public._otp_issue(v_raw, 'phone_change',
    'Telefon değişikliği' || coalesce(' · ' || nullif(v_name, ''), ''));
end;
$function$;
revoke all on function public.phone_change_send(text, text) from public, anon;
grant execute on function public.phone_change_send(text, text) to authenticated;

-- Kod doğruysa giriş numarası (auth e-postası ve telefon), oyuncu kaydı ve
-- kullanıcı kaydı yeni numaraya geçer.
create or replace function public.phone_change_confirm(
  p_tc text, p_new_phone text, p_code text
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_raw text := public.phone_raw10(p_new_phone);
  v_res text := public._phone_change_guard(p_tc, v_raw);
  v_email text := v_raw || '@masterclass.com';
  v_phone text := '90' || v_raw;
begin
  if v_res <> 'ok' then
    return v_res;
  end if;
  v_res := public._otp_consume(v_raw, p_code);
  if v_res <> 'ok' then
    return v_res;
  end if;

  if exists (select 1 from auth.users where phone = v_phone and id <> v_uid) then
    v_phone := null;
  end if;

  update auth.users
     set email = v_email, phone = v_phone, updated_at = now()
   where id = v_uid;
  update auth.identities
     set identity_data = identity_data || jsonb_build_object('email', v_email),
         updated_at = now()
   where user_id = v_uid and provider = 'email';

  update public.players set phone = v_raw where auth_uid = v_uid;

  -- Yeni numarada hesapsız eski bir kullanıcı satırı varsa yer açılır.
  delete from public.app_users
   where phone = v_raw and auth_uid is null;
  update public.app_users set phone = v_raw where auth_uid = v_uid::text;

  insert into public.identity_events (action, user_id)
  values ('phone_change', v_uid);
  return 'ok';
end;
$function$;
revoke all on function public.phone_change_confirm(text, text, text) from public, anon;
grant execute on function public.phone_change_confirm(text, text, text) to authenticated;
