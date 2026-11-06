-- Taraftar kaydında il/ilçe isteğe bağlı (verilirse birbirine uymalı).
alter table public.fan_members alter column province_id drop not null;
alter table public.fan_members alter column district_id drop not null;

CREATE OR REPLACE FUNCTION public.register_fan(p_phone text, p_code text, p_password text, p_first text, p_last text, p_province_id integer, p_district_id integer, p_terms_version text, p_terms_accepted boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_first text := btrim(coalesce(p_first, ''));
  v_last text := btrim(coalesce(p_last, ''));
  v_uid uuid;
  v_otp text;
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if length(v_first) < 2 or length(v_last) < 2
     or length(v_first) > 40 or length(v_last) > 40 then
    return 'invalid_name';
  end if;
  if p_password is null or length(p_password) not between 6 and 10
     or p_password !~ '[^A-Za-z]' then
    return 'weak_password';
  end if;
  if not coalesce(p_terms_accepted, false)
     or coalesce(p_terms_version, '') <> '2026-11-v1' then
    return 'terms_required';
  end if;
  if (p_province_id is null) <> (p_district_id is null)
     or (p_province_id is not null and not exists (
       select 1 from public.turkey_districts
        where id = p_district_id and province_id = p_province_id)) then
    return 'invalid_location';
  end if;
  if exists (
    select 1 from auth.users where email = v_raw || '@masterclass.com'
  ) then
    return 'has_account';
  end if;

  v_otp := public._otp_consume(v_raw, p_code);
  if v_otp <> 'ok' then
    return v_otp;
  end if;

  v_uid := public.set_phone_account_password(
    v_raw, p_password, false, v_first || ' ' || v_last
  );
  update public.app_users
     set role = 'fan'
   where auth_uid = v_uid::text;

  insert into public.fan_members (
    user_id, phone_raw10, first_name, last_name, province_id, district_id,
    terms_version, terms_accepted_at
  ) values (
    v_uid, v_raw, v_first, v_last, p_province_id, p_district_id,
    p_terms_version, now()
  );
  return 'ok';
end;
$function$;
