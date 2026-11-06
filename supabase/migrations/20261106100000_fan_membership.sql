-- Taraftar signup uses the existing OTP provider and rate limits.
create table if not exists public.fan_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  phone_raw10 text not null unique check (phone_raw10 ~ '^5[0-9]{9}$'),
  first_name text not null,
  last_name text not null,
  province_id integer not null references public.turkey_provinces(id),
  district_id integer not null references public.turkey_districts(id),
  terms_version text not null,
  terms_accepted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint fan_member_district_matches_province
    foreign key (province_id, district_id)
    references public.turkey_districts(province_id, id)
);

alter table public.fan_members enable row level security;
drop policy if exists fan_members_read_own on public.fan_members;
create policy fan_members_read_own on public.fan_members
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
grant select on public.fan_members to authenticated;

-- A dedicated entry point keeps existing player and organizer OTP messages unchanged.
create or replace function public.fan_register_otp_send(
  p_phone text,
  p_name text
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_name text := btrim(coalesce(p_name, ''));
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if length(v_name) < 3 or length(v_name) > 80 then
    return 'invalid_name';
  end if;
  if exists (
    select 1 from auth.users where email = v_raw || '@masterclass.com'
  ) then
    return 'has_account';
  end if;
  return public._otp_issue(v_raw, 'register', 'Lig Masası taraftar kaydı · ' || v_name);
end;
$$;
revoke all on function public.fan_register_otp_send(text, text) from public;
grant execute on function public.fan_register_otp_send(text, text) to anon, authenticated;

create or replace function public.register_fan(
  p_phone text,
  p_code text,
  p_password text,
  p_first text,
  p_last text,
  p_province_id integer,
  p_district_id integer,
  p_terms_version text,
  p_terms_accepted boolean
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
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
  if not exists (
    select 1 from public.turkey_districts
     where id = p_district_id and province_id = p_province_id
  ) then
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
$$;
revoke all on function public.register_fan(
  text, text, text, text, text, integer, integer, text, boolean
) from public;
grant execute on function public.register_fan(
  text, text, text, text, text, integer, integer, text, boolean
) to anon, authenticated;
