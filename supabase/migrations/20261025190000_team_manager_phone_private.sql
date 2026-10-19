-- teams herkese açık okunur; sorumlunun telefonu orada durmamalı.
-- Telefon ayrı tabloya (team_manager_contacts) taşınır; yalnız takımı
-- yönetebilenler okur. Atama tek RPC'den yapılır: set_team_manager.
-- teams.manager_name (herkese açık ad) ve manager_id kalır.

create table if not exists public.team_manager_contacts (
  team_id     uuid primary key references public.teams (id) on delete cascade,
  phone_raw10 text not null check (phone_raw10 ~ '^5[0-9]{9}$'),
  updated_at  timestamptz not null default now()
);
create index if not exists team_manager_contacts_phone_idx
  on public.team_manager_contacts (phone_raw10);

alter table public.team_manager_contacts enable row level security;
drop policy if exists team_manager_contacts_read on public.team_manager_contacts;
create policy team_manager_contacts_read on public.team_manager_contacts
  for select to authenticated using (public.owns_team(team_id));

insert into public.team_manager_contacts (team_id, phone_raw10)
select id, manager_phone from public.teams where manager_phone is not null
on conflict (team_id) do update set phone_raw10 = excluded.phone_raw10;

drop trigger if exists teams_manager_sync on public.teams;
drop trigger if exists teams_manager_fill on public.teams;
drop function if exists public.trg_teams_manager_fill();
alter table public.teams drop column if exists manager_phone;

-- Yetki: futbolcunun hesabı, yoksa telefonun hesabı.
create or replace function public.sync_team_managers(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid;
  v_phone text;
begin
  select p.auth_uid into v_uid
  from public.teams t
  join public.players p on p.id = t.manager_id
  where t.id = p_team_id;

  if v_uid is null then
    select c.phone_raw10 into v_phone
    from public.team_manager_contacts c where c.team_id = p_team_id;
    if v_phone is not null then
      v_uid := public.account_uid_for_phone(v_phone);
    end if;
  end if;

  -- Sorumlu değiştiyse / kaldırıldıysa eski hesapların yetkisi düşer.
  delete from public.team_managers tm
  where tm.team_id = p_team_id
    and (v_uid is null or tm.user_id <> v_uid);

  if v_uid is not null then
    insert into public.team_managers (season_id, team_id, user_id)
    select st.season_id, p_team_id, v_uid
    from public.season_teams st
    where st.team_id = p_team_id
    on conflict do nothing;
  end if;
end;
$$;

-- Eski derlemeler yalnız manager_id yazar (futbolcu seçici): ad ve telefon
-- futbolcudan doldurulur. set_team_manager kendi yazdığında atlanır.
create or replace function public.trg_teams_manager_fill()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_phone text;
begin
  if coalesce(current_setting('app.team_manager_rpc', true), '') = '1' then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.manager_id is not distinct from old.manager_id then
    return new;
  end if;
  if new.manager_id is null then
    new.manager_name := null;
    delete from public.team_manager_contacts where team_id = new.id;
    return new;
  end if;
  select trim(concat_ws(' ', nullif(trim(p.name), ''), nullif(trim(p.surname), ''))),
         public.phone_raw10(p.phone)
    into new.manager_name, v_phone
  from public.players p where p.id = new.manager_id;
  if v_phone ~ '^5[0-9]{9}$' and tg_op = 'UPDATE' then
    insert into public.team_manager_contacts (team_id, phone_raw10)
    values (new.id, v_phone)
    on conflict (team_id) do update set phone_raw10 = excluded.phone_raw10, updated_at = now();
  else
    delete from public.team_manager_contacts where team_id = new.id;
  end if;
  return new;
end;
$$;

create trigger teams_manager_fill
  before insert or update of manager_id on public.teams
  for each row execute function public.trg_teams_manager_fill();

-- Yeni takımda (insert) iletişim satırı takım satırı oluştuktan sonra yazılır.
create or replace function public.trg_teams_manager_contact_after_insert()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_phone text;
begin
  if new.manager_id is not null
     and coalesce(current_setting('app.team_manager_rpc', true), '') <> '1' then
    select public.phone_raw10(p.phone) into v_phone
    from public.players p where p.id = new.manager_id;
    if v_phone ~ '^5[0-9]{9}$' then
      insert into public.team_manager_contacts (team_id, phone_raw10)
      values (new.id, v_phone)
      on conflict (team_id) do update set phone_raw10 = excluded.phone_raw10;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists teams_manager_contact_ins on public.teams;
create trigger teams_manager_contact_ins
  after insert on public.teams
  for each row execute function public.trg_teams_manager_contact_after_insert();

create trigger teams_manager_sync
  after insert or update of manager_id on public.teams
  for each row execute function public.trg_teams_manager_sync();

-- Takım sorumlusunu telefonla atar (boş telefon = sorumluyu kaldır).
-- Telefon bir futbolcuya ya da hesaba kayıtlıysa ad oradan gelir; değilse
-- girilen ad kullanılır. Döner: kaydedilen ad.
create or replace function public.set_team_manager(
  p_team_id uuid,
  p_phone text,
  p_full_name text default null
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(nullif(trim(coalesce(p_phone, '')), ''));
  v_pid uuid;
  v_name text;
begin
  if not public.owns_team(p_team_id) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  perform set_config('app.team_manager_rpc', '1', true);

  if v_raw is null then
    delete from public.team_manager_contacts where team_id = p_team_id;
    update public.teams set manager_id = null, manager_name = null
    where id = p_team_id;
    perform public.sync_team_managers(p_team_id);
    perform set_config('app.team_manager_rpc', '', true);
    return null;
  end if;

  if v_raw !~ '^5[0-9]{9}$' then
    raise exception 'Geçerli bir cep telefonu girin (5XX XXX XX XX).';
  end if;

  -- Mevcut futbolcu bu telefondaysa korunur (aynı telefonda birden çok
  -- kayıt olabilir); değilse telefonla eşleşen futbolcu aranır.
  select t.manager_id into v_pid
  from public.teams t
  join public.players p on p.id = t.manager_id
  where t.id = p_team_id and public.phone_raw10(p.phone) = v_raw;
  if v_pid is null then
    select p.id into v_pid from public.players p
    where public.phone_raw10(p.phone) = v_raw
    order by (p.auth_uid is null), p.id limit 1;
  end if;

  select full_name into v_name from public.person_name_for_phone(v_raw);
  v_name := left(coalesce(v_name, nullif(trim(coalesce(p_full_name, '')), '')), 80);
  if v_name is null then
    raise exception 'Takım sorumlusunun ad soyadını girin.';
  end if;

  insert into public.team_manager_contacts (team_id, phone_raw10)
  values (p_team_id, v_raw)
  on conflict (team_id) do update set phone_raw10 = excluded.phone_raw10, updated_at = now();
  update public.teams set manager_id = v_pid, manager_name = v_name
  where id = p_team_id;
  perform public.sync_team_managers(p_team_id);
  perform set_config('app.team_manager_rpc', '', true);
  return v_name;
end;
$$;
revoke all on function public.set_team_manager(uuid, text, text) from public, anon;
grant execute on function public.set_team_manager(uuid, text, text) to authenticated;

-- Futbolcu olmayan sorumlu hesap açınca yetkisi bağlanır; panelde adı
-- görünsün diye app_users kaydı da açılır.
create or replace function public.on_auth_user_created_link_team_manager()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := split_part(coalesce(new.email, ''), '@', 1);
  v_name text;
  r record;
begin
  if v_raw !~ '^5[0-9]{9}$' then
    return new;
  end if;
  for r in
    select t.id, t.manager_name from public.team_manager_contacts c
    join public.teams t on t.id = c.team_id
    where c.phone_raw10 = v_raw
  loop
    perform public.sync_team_managers(r.id);
    v_name := coalesce(v_name, r.manager_name);
  end loop;
  if v_name is not null then
    insert into public.app_users (phone, name, auth_uid, role)
    values (v_raw, v_name, new.id::text, 'player')
    on conflict (phone) do update
      set auth_uid = excluded.auth_uid,
          name = coalesce(public.app_users.name, excluded.name);
  end if;
  return new;
end;
$$;

-- Kayıt talebi: futbolcu olmayan takım sorumlusu da kayıt olabilir.
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
     )
     and not exists (
       select 1 from public.region_owner_invites i where i.phone_raw10 = v_raw
     )
     and not exists (
       select 1 from public.team_manager_contacts c where c.phone_raw10 = v_raw
     ) then
    return 'unknown_phone';
  end if;

  -- Davetli sahibin / sorumlunun adı talepte görünsün.
  if v_name is null then
    select full_name into v_name from (
      select full_name, created_at from public.league_owner_invites
      where phone_raw10 = v_raw
      union all
      select full_name, created_at from public.region_owner_invites
      where phone_raw10 = v_raw
      union all
      select t.manager_name, c.updated_at from public.team_manager_contacts c
      join public.teams t on t.id = c.team_id
      where c.phone_raw10 = v_raw
    ) i order by created_at limit 1;
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
