-- Turnuva sahiplerinin admin tarafından ad soyad + telefonla eklenmesi.
--
-- * league_owner_invites: turnuvaya eklenen sahiplerin adı ve telefonu.
--   Telefonun hesabı varsa kişi hemen league_owners'a yazılır; yoksa davet
--   bekler ve hesap açıldığı anda (auth.users insert tetikleyicisi) bağlanır.
-- * Davetli telefon kayıt olabilir (request_account_password artık
--   'unknown_phone' döndürmez).
-- * Yönetim RPC'leri yalnız admin: list/add/remove_league_owner.

create table if not exists public.league_owner_invites (
  league_id   uuid not null references public.leagues (id) on delete cascade,
  phone_raw10 text not null check (phone_raw10 ~ '^5[0-9]{9}$'),
  full_name   text not null,
  user_id     uuid references auth.users (id) on delete set null,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  primary key (league_id, phone_raw10)
);
create index if not exists league_owner_invites_phone_idx
  on public.league_owner_invites (phone_raw10);

alter table public.league_owner_invites enable row level security;
drop policy if exists league_owner_invites_admin on public.league_owner_invites;
create policy league_owner_invites_admin on public.league_owner_invites
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Telefonun hesabı (hesaplar <telefon>@masterclass.com e-postasıyla açılır).
create or replace function public.account_uid_for_phone(p_raw10 text)
returns uuid
language sql
stable
security definer
set search_path to ''
as $$
  select id from auth.users where email = p_raw10 || '@masterclass.com' limit 1;
$$;
revoke all on function public.account_uid_for_phone(text) from public, anon, authenticated;

-- Bekleyen davetleri hesaba bağlar; profil ekranında ad görünsün diye
-- app_users kaydı da açılır.
create or replace function public.link_league_owner_invites(p_raw10 text, p_uid uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_name text;
begin
  update public.league_owner_invites
  set user_id = p_uid
  where phone_raw10 = p_raw10 and user_id is distinct from p_uid;

  insert into public.league_owners (league_id, user_id)
  select league_id, p_uid from public.league_owner_invites
  where phone_raw10 = p_raw10
  on conflict do nothing;

  select full_name into v_name from public.league_owner_invites
  where phone_raw10 = p_raw10 order by created_at limit 1;
  if v_name is not null then
    insert into public.app_users (phone, name, auth_uid, role)
    values (p_raw10, v_name, p_uid::text, 'player')
    on conflict (phone) do update
      set auth_uid = excluded.auth_uid,
          name = coalesce(public.app_users.name, excluded.name);
  end if;
end;
$$;
revoke all on function public.link_league_owner_invites(text, uuid) from public, anon, authenticated;

-- Yeni hesap açılınca davetler bağlanır.
create or replace function public.on_auth_user_created_link_owner()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := split_part(coalesce(new.email, ''), '@', 1);
begin
  if v_raw ~ '^5[0-9]{9}$' and exists (
    select 1 from public.league_owner_invites where phone_raw10 = v_raw
  ) then
    perform public.link_league_owner_invites(v_raw, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists link_league_owner_on_signup on auth.users;
create trigger link_league_owner_on_signup
  after insert on auth.users
  for each row execute function public.on_auth_user_created_link_owner();

-- Liste: davetler + (eski usulle eklenmiş) davetsiz sahipler.
create or replace function public.list_league_owners(p_league_id uuid)
returns table (phone_raw10 text, full_name text, user_id uuid, has_account boolean)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  return query
    select i.phone_raw10, i.full_name, i.user_id, i.user_id is not null
    from public.league_owner_invites i
    where i.league_id = p_league_id
    union all
    select split_part(u.email, '@', 1),
           coalesce(nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
                    split_part(u.email, '@', 1)),
           o.user_id, true
    from public.league_owners o
    join auth.users u on u.id = o.user_id
    where o.league_id = p_league_id
      and not exists (
        select 1 from public.league_owner_invites i
        where i.league_id = o.league_id and i.user_id = o.user_id
      )
    order by 2;
end;
$$;

create or replace function public.add_league_owner(
  p_league_id uuid,
  p_full_name text,
  p_phone text
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_uid uuid;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    raise exception 'Geçerli bir cep telefonu girin (5XX XXX XX XX).';
  end if;
  if v_name is null then
    raise exception 'Ad soyad girin.';
  end if;

  insert into public.league_owner_invites (league_id, phone_raw10, full_name)
  values (p_league_id, v_raw, left(v_name, 80))
  on conflict (league_id, phone_raw10) do update set full_name = excluded.full_name;

  v_uid := public.account_uid_for_phone(v_raw);
  if v_uid is null then
    return 'invited';
  end if;
  perform public.link_league_owner_invites(v_raw, v_uid);
  return 'linked';
end;
$$;

create or replace function public.remove_league_owner(p_league_id uuid, p_phone text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_uid uuid;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  v_uid := public.account_uid_for_phone(v_raw);
  delete from public.league_owner_invites
  where league_id = p_league_id and phone_raw10 = v_raw;
  if v_uid is not null then
    delete from public.league_owners
    where league_id = p_league_id and user_id = v_uid;
  end if;
end;
$$;

revoke all on function public.list_league_owners(uuid) from public, anon;
revoke all on function public.add_league_owner(uuid, text, text) from public, anon;
revoke all on function public.remove_league_owner(uuid, text) from public, anon;
grant execute on function public.list_league_owners(uuid) to authenticated;
grant execute on function public.add_league_owner(uuid, text, text) to authenticated;
grant execute on function public.remove_league_owner(uuid, text) to authenticated;

-- Kayıt talebi: davetli turnuva sahipleri de kayıt olabilir.
create or replace function public.request_account_password(
  p_phone text,
  p_full_name text default null,
  p_reset boolean default false
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_has_account boolean;
  v_kind text;
begin
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;

  select exists (
    select 1 from auth.users where email = v_raw || '@masterclass.com'
  ) into v_has_account;

  if p_reset and not v_has_account then
    return 'not_registered';
  end if;

  if not v_has_account
     and not exists (
       select 1 from public.players p where public.phone_raw10(p.phone) = v_raw
     )
     and not exists (
       select 1 from public.league_owner_invites i where i.phone_raw10 = v_raw
     ) then
    return 'unknown_phone';
  end if;

  -- Davetli sahibin adı talepte görünsün.
  if v_name is null then
    select full_name into v_name from public.league_owner_invites
    where phone_raw10 = v_raw order by created_at limit 1;
  end if;

  v_kind := case when v_has_account then 'reset' else 'register' end;

  update public.account_requests
  set kind = v_kind,
      full_name = coalesce(v_name, full_name)
  where phone_raw10 = v_raw and status = 'pending';
  if found then
    return 'already_pending';
  end if;

  insert into public.account_requests (phone_raw10, kind, full_name)
  values (v_raw, v_kind, left(v_name, 80));

  return case when v_has_account then 'reset_requested' else 'requested' end;
end;
$$;
