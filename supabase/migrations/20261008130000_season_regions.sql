-- Bölgeler: Turnuva > Sezon > Bölge > Grup.
--
-- Bir sezon farklı illerde oynanabilir (İstanbul (Avrupa), İstanbul (Anadolu),
-- Ankara...). Her bölgenin kendi sorumluları (region_owners) vardır; bölge
-- sorumlusu yalnızca kendi bölgesinin gruplarını, takımlarını, maçlarını,
-- kadrolarını ve cezalarını yönetir. Turnuva sahipleri (kurucu başkan)
-- turnuvanın her şeyini yönetmeye devam eder. Bölgesiz grup ve maçlar
-- (ör. bölgeler arası final) yalnızca kurucuya kalır.

create table if not exists public.season_regions (
  id         uuid primary key default gen_random_uuid(),
  season_id  uuid not null references public.seasons (id) on delete cascade,
  name       text not null check (length(trim(name)) > 0),
  city       text,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (season_id, name)
);
create index if not exists season_regions_season_idx on public.season_regions (season_id);

drop trigger if exists set_updated_at on public.season_regions;
create trigger set_updated_at before update on public.season_regions
  for each row execute function public.set_updated_at();

alter table public.groups
  add column if not exists region_id uuid
  references public.season_regions (id) on delete set null;
create index if not exists groups_region_idx on public.groups (region_id);

-- Grubun bölgesi aynı sezondan olmalı.
create or replace function public.groups_region_same_season()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.region_id is not null and not exists (
    select 1 from public.season_regions r
    where r.id = new.region_id and r.season_id = new.season_id
  ) then
    raise exception 'Bölge bu sezona ait değil.';
  end if;
  return new;
end;
$$;
drop trigger if exists groups_region_same_season on public.groups;
create trigger groups_region_same_season
  before insert or update of region_id, season_id on public.groups
  for each row execute function public.groups_region_same_season();

create table if not exists public.region_owners (
  region_id  uuid not null references public.season_regions (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (region_id, user_id)
);
create index if not exists region_owners_user_idx on public.region_owners (user_id);

create table if not exists public.region_owner_invites (
  region_id   uuid not null references public.season_regions (id) on delete cascade,
  phone_raw10 text not null check (phone_raw10 ~ '^5[0-9]{9}$'),
  full_name   text not null,
  user_id     uuid references auth.users (id) on delete set null,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  primary key (region_id, phone_raw10)
);
create index if not exists region_owner_invites_phone_idx
  on public.region_owner_invites (phone_raw10);

-- Yetki fonksiyonları ----------------------------------------------------------

-- Bölgeyi yönetebilir mi: admin, kurucu ya da bölge sorumlusu.
create or replace function public.owns_region(p_region_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.is_admin() or exists (
    select 1 from public.season_regions r
    where r.id = p_region_id
      and (public.owns_season(r.season_id) or exists (
        select 1 from public.region_owners ro
        where ro.region_id = r.id and ro.user_id = auth.uid()))
  )
$$;

-- Grubu yönetebilir mi: kurucu ya da grubun bölge sorumlusu.
create or replace function public.owns_group(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.is_admin() or exists (
    select 1 from public.groups g
    where g.id = p_group_id
      and (public.owns_season(g.season_id) or exists (
        select 1 from public.region_owners ro
        where ro.region_id = g.region_id and ro.user_id = auth.uid()))
  )
$$;

-- Sezondaki takımı yönetebilir mi (takımın grubu üzerinden bölge).
create or replace function public.owns_season_team(p_season_id uuid, p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.owns_season(p_season_id) or exists (
    select 1 from public.season_teams st
    join public.groups g on g.id = st.group_id
    join public.region_owners ro on ro.region_id = g.region_id
    where st.season_id = p_season_id and st.team_id = p_team_id
      and ro.user_id = auth.uid()
  )
$$;

-- Sezondaki oyuncuyu yönetebilir mi (oyuncunun o sezondaki takımı üzerinden).
create or replace function public.owns_season_player(p_season_id uuid, p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.owns_season(p_season_id) or exists (
    select 1 from public.season_team_players stp
    join public.season_teams st
      on st.season_id = stp.season_id and st.team_id = stp.team_id
    join public.groups g on g.id = st.group_id
    join public.region_owners ro on ro.region_id = g.region_id
    where stp.season_id = p_season_id and stp.player_id = p_player_id
      and ro.user_id = auth.uid()
  )
$$;

-- Maç: kurucu ya da maçın grubunun bölge sorumlusu.
create or replace function public.owns_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.is_admin() or exists (
    select 1
    from public.matches m
    left join public.seasons s on s.id = m.season_id
    join public.league_owners o
      on o.league_id = coalesce(m.league_id, s.league_id)
    where m.id = p_match_id and o.user_id = auth.uid()
  ) or exists (
    select 1
    from public.matches m
    join public.groups g on g.id = m.group_id
    join public.region_owners ro on ro.region_id = g.region_id
    where m.id = p_match_id and ro.user_id = auth.uid()
  )
$$;

grant execute on function public.owns_region(uuid) to authenticated;
grant execute on function public.owns_group(uuid) to authenticated;
grant execute on function public.owns_season_team(uuid, uuid) to authenticated;
grant execute on function public.owns_season_player(uuid, uuid) to authenticated;

-- RLS --------------------------------------------------------------------------
alter table public.season_regions enable row level security;
drop policy if exists season_regions_read on public.season_regions;
create policy season_regions_read on public.season_regions for select
  using (public.can_view_season(season_id));
drop policy if exists season_regions_write on public.season_regions;
create policy season_regions_write on public.season_regions
  for all to authenticated
  using (public.owns_season(season_id))
  with check (public.owns_season(season_id));
grant select on public.season_regions to anon, authenticated;
grant insert, update, delete on public.season_regions to authenticated;

alter table public.region_owners enable row level security;
drop policy if exists region_owners_read on public.region_owners;
create policy region_owners_read on public.region_owners for select
  to authenticated
  using (user_id = auth.uid() or public.owns_region(region_id));
grant select on public.region_owners to authenticated;

alter table public.region_owner_invites enable row level security;
-- Davetler yalnızca RPC'lerle yönetilir.

drop policy if exists groups_write on public.groups;
create policy groups_write on public.groups for all to authenticated
  using (public.owns_season(season_id) or public.owns_region(region_id))
  with check (public.owns_season(season_id) or public.owns_region(region_id));

drop policy if exists matches_write on public.matches;
create policy matches_write on public.matches for all to authenticated
  using (public.owns_league(coalesce(league_id, (
           select s.league_id from public.seasons s where s.id = matches.season_id)))
         or public.owns_group(group_id))
  with check (public.owns_league(coalesce(league_id, (
           select s.league_id from public.seasons s where s.id = matches.season_id)))
         or public.owns_group(group_id));

drop policy if exists season_teams_write on public.season_teams;
create policy season_teams_write on public.season_teams for all to authenticated
  using (public.owns_season(season_id) or public.owns_group(group_id))
  with check (public.owns_season(season_id) or public.owns_group(group_id));

drop policy if exists season_registrations_write on public.season_registrations;
create policy season_registrations_write on public.season_registrations
  for all to authenticated
  using (public.owns_season(season_id) or public.owns_group(group_id))
  with check (public.owns_season(season_id) or public.owns_group(group_id));

drop policy if exists season_team_players_write on public.season_team_players;
create policy season_team_players_write on public.season_team_players
  for all to authenticated
  using (public.owns_season_team(season_id, team_id))
  with check (public.owns_season_team(season_id, team_id));

drop policy if exists team_managers_write on public.team_managers;
create policy team_managers_write on public.team_managers for all to authenticated
  using (public.owns_season_team(season_id, team_id))
  with check (public.owns_season_team(season_id, team_id));
drop policy if exists team_managers_read on public.team_managers;
create policy team_managers_read on public.team_managers for select
  using (user_id = auth.uid() or public.owns_season_team(season_id, team_id));

drop policy if exists player_penalties_write on public.player_penalties;
create policy player_penalties_write on public.player_penalties
  for all to authenticated
  using (public.owns_season_player(season_id, player_id))
  with check (public.owns_season_player(season_id, player_id));

drop policy if exists player_season_stats_write on public.player_season_stats;
create policy player_season_stats_write on public.player_season_stats
  for all to authenticated
  using (public.owns_season_player(season_id, player_id))
  with check (public.owns_season_player(season_id, player_id));

drop policy if exists pending_actions_insert on public.pending_actions;
create policy pending_actions_insert on public.pending_actions
  for insert to authenticated
  with check (public.manages_team(season_id, team_id)
              or public.owns_season_team(season_id, team_id));
drop policy if exists pending_actions_read on public.pending_actions;
create policy pending_actions_read on public.pending_actions for select
  to authenticated
  using (submitted_by = auth.uid() or public.owns_league(league_id)
         or public.owns_season_team(season_id, team_id));

-- Gizli turnuva görünürlüğü: bölge sorumlusu kendi turnuvasını görür.
create or replace function public.is_region_owner_of_league(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1 from public.region_owners ro
    join public.season_regions r on r.id = ro.region_id
    join public.seasons s on s.id = r.season_id
    where s.league_id = p_league_id and ro.user_id = auth.uid()
  )
$$;

-- Kart cezası bildirimi: bölge sorumlularına da gider.
CREATE OR REPLACE FUNCTION public.match_events_card_penalty()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_kind text;
  v_count int;
  v_season uuid;
  v_league uuid;
  v_name text;
  v_id uuid;
  v_owners uuid[];
begin
  if new.player_id is null then
    return new;
  end if;
  if new.event_type = 'red_card' then
    v_kind := 'red_card';
    v_count := 2;
  elsif new.event_type = 'yellow_card' and exists (
    select 1 from public.match_events e
    where e.match_id = new.match_id
      and e.player_id = new.player_id
      and e.event_type = 'yellow_card'
      and e.id <> new.id
  ) then
    v_kind := 'second_yellow';
    v_count := 1;
  else
    return new;
  end if;

  select season_id, league_id into v_season, v_league
  from public.matches where id = new.match_id;
  if v_season is null then
    return new;
  end if;

  insert into public.player_penalties
    (player_id, season_id, match_count, penalty_reason, is_active, status,
     kind, match_id, source_event_id)
  values
    (new.player_id, v_season, v_count,
     case v_kind when 'red_card' then 'Kırmızı kart' else 'İkinci sarı kart' end,
     false, 'pending', v_kind, new.match_id, new.id)
  on conflict do nothing
  returning id into v_id;

  if v_id is not null then
    select trim(coalesce(name, '') || ' ' || coalesce(surname, ''))
      into v_name from public.players where id = new.player_id;
    -- Kurucu başkanlar + maçın bölge sorumluları.
    select array_agg(distinct uid) into v_owners from (
      select user_id as uid from public.league_owners where league_id = v_league
      union
      select ro.user_id from public.matches m
      join public.groups g on g.id = m.group_id
      join public.region_owners ro on ro.region_id = g.region_id
      where m.id = new.match_id
    ) x;
    perform public.push_send(
      v_owners,
      'Onay bekleyen ceza',
      coalesce(v_name, 'Oyuncu') || ' · ' ||
        case v_kind when 'red_card' then 'Kırmızı kart (2 maç)'
                    else 'İkinci sarı kart (1 maç)' end,
      '/',
      'penalty-' || v_id
    );
  end if;
  return new;
exception when others then
  raise warning 'card penalty: %', sqlerrm;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_player_penalty(p_penalty_id uuid, p_approve boolean, p_match_count integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_season uuid;
  v_player uuid;
  v_count int;
  v_remaining int;
begin
  select season_id, player_id, coalesce(p_match_count, match_count)
    into v_season, v_player, v_count
  from public.player_penalties where id = p_penalty_id;
  if v_season is null then
    raise exception 'Ceza bulunamadı.';
  end if;
  if not public.owns_season_player(v_season, v_player) then
    raise exception 'Bu cezayı onaylama yetkiniz yok.';
  end if;

  if not p_approve then
    update public.player_penalties
       set status = 'rejected', is_active = false,
           reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_penalty_id;
    return;
  end if;

  if v_count is null or v_count < 1 then
    raise exception 'Ceza en az 1 maç olmalı.';
  end if;
  v_remaining := greatest(v_count - public.penalty_served_matches(p_penalty_id), 0);
  update public.player_penalties
     set status = 'approved', match_count = v_count,
         remaining_matches = v_remaining, is_active = v_remaining > 0,
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_penalty_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_pending_action(p_action_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  a         public.pending_actions;
  v_player  uuid;
  v_jersey  smallint;
  v_p       jsonb;
  v_current public.season_team_players;
begin
  select * into a from public.pending_actions
  where id = p_action_id
  for update;

  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if not (public.owns_league(a.league_id)
          or public.owns_season_team(a.season_id, a.team_id)) then
    raise exception 'Bu talebi inceleme yetkiniz yok.';
  end if;
  if a.status <> 'pending' then
    raise exception 'Talep zaten sonuçlanmış (%).', a.status;
  end if;

  if p_approve then
    v_player := nullif(a.payload ->> 'player_id', '')::uuid;
    v_jersey := nullif(a.payload ->> 'jersey_number', '')::smallint;

    if a.action_type = 'roster_add' then
      if v_player is null then
        v_p := a.payload -> 'player';
        if v_p is null
           or coalesce(trim(v_p ->> 'name'), '') = ''
           or coalesce(trim(v_p ->> 'surname'), '') = ''
           or nullif(v_p ->> 'birth_date', '') is null then
          raise exception 'Yeni oyuncu için ad, soyad ve doğum tarihi gerekli.';
        end if;
        insert into public.players (
          name, surname, birth_date, phone, main_position, preferred_foot
        ) values (
          trim(v_p ->> 'name'),
          trim(v_p ->> 'surname'),
          (v_p ->> 'birth_date')::date,
          public.phone_raw10(v_p ->> 'phone'),
          nullif(trim(v_p ->> 'main_position'), ''),
          nullif(trim(v_p ->> 'preferred_foot'), '')
        )
        returning id into v_player;
      end if;

      select * into v_current from public.season_team_players
      where season_id = a.season_id and player_id = v_player;

      if found and v_current.is_active and v_current.team_id <> a.team_id then
        raise exception 'Oyuncu bu sezon başka bir takımda kayıtlı.';
      end if;

      if found then
        update public.season_team_players
        set team_id = a.team_id,
            is_active = true,
            jersey_number = coalesce(v_jersey, jersey_number)
        where id = v_current.id;
      else
        insert into public.season_team_players (
          season_id, team_id, player_id, jersey_number, is_active
        ) values (a.season_id, a.team_id, v_player, v_jersey, true);
      end if;

    elsif a.action_type = 'roster_remove' then
      update public.season_team_players
      set is_active = false
      where season_id = a.season_id
        and team_id = a.team_id
        and player_id = v_player;
      if not found then
        raise exception 'Oyuncu bu takımın kadrosunda değil.';
      end if;

    elsif a.action_type = 'jersey_change' then
      if v_jersey is not null and exists (
        select 1 from public.season_team_players
        where season_id = a.season_id and team_id = a.team_id
          and jersey_number = v_jersey and is_active
          and player_id <> v_player
      ) then
        raise exception 'Bu forma numarası takımda kullanılıyor.';
      end if;
      update public.season_team_players
      set jersey_number = v_jersey
      where season_id = a.season_id
        and team_id = a.team_id
        and player_id = v_player
        and is_active;
      if not found then
        raise exception 'Oyuncu bu takımın aktif kadrosunda değil.';
      end if;
    end if;
  end if;

  update public.pending_actions
  set status = case when p_approve then 'approved' else 'rejected' end,
      review_note = p_note,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      payload = case
        when p_approve and a.action_type = 'roster_add' and v_player is not null
          then payload || jsonb_build_object('player_id', v_player)
        else payload
      end
  where id = a.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.match_audience(p_match_id uuid, p_include_followers boolean)
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with m as (
    select season_id, league_id, group_id, home_team_id, away_team_id
    from public.matches where id = p_match_id
  ),
  ids as (
    select p.auth_uid as uid
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    join m on stp.season_id = m.season_id
      and stp.team_id in (m.home_team_id, m.away_team_id)
    where stp.is_active
    union
    select tm.user_id from public.team_managers tm
    join m on tm.season_id = m.season_id
      and tm.team_id in (m.home_team_id, m.away_team_id)
    union
    select o.user_id from public.league_owners o
    join m on o.league_id = m.league_id
    union
    select ro.user_id from m
    join public.groups g on g.id = m.group_id
    join public.region_owners ro on ro.region_id = g.region_id
    union
    select f.user_id from public.league_followers f
    join m on f.league_id = m.league_id
    where p_include_followers
  )
  select coalesce(array_agg(distinct uid), '{}') from ids where uid is not null
$function$;

CREATE OR REPLACE FUNCTION public.request_account_password(p_phone text, p_full_name text DEFAULT NULL::text, p_reset boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
     ) then
    return 'unknown_phone';
  end if;

  -- Davetli sahibin adı talepte görünsün.
  if v_name is null then
    select full_name into v_name from (
      select full_name, created_at from public.league_owner_invites
      where phone_raw10 = v_raw
      union all
      select full_name, created_at from public.region_owner_invites
      where phone_raw10 = v_raw
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
$function$;

create or replace function public.can_view_league(p_league_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text;
begin
  if p_league_id is null then
    return true;
  end if;
  if not public.private_leagues_enabled() then
    return true;
  end if;
  if not exists (
    select 1 from public.leagues where id = p_league_id and is_private
  ) then
    return true;
  end if;
  if v_uid is null then
    return false;
  end if;
  if public.owns_league(p_league_id)
     or public.is_region_owner_of_league(p_league_id) then
    return true;
  end if;

  -- Kodla takip (kod hâlâ geçerliyse).
  if exists (
    select 1 from public.league_followers f
    join public.leagues l on l.id = f.league_id
    where f.league_id = p_league_id and f.user_id = v_uid
      and lower(f.code) = lower(coalesce(l.access_code, ''))
  ) then
    return true;
  end if;

  -- Maç gözlemcisi.
  if exists (
    select 1 from public.matches m
    where m.league_id = p_league_id and m.observer_id = v_uid
  ) then
    return true;
  end if;

  -- Takım sorumlusu (sezon bazında ya da takımın sorumlusu).
  if exists (
    select 1 from public.team_managers tm
    join public.seasons s on s.id = tm.season_id
    where s.league_id = p_league_id and tm.user_id = v_uid
  ) or exists (
    select 1 from public.season_teams st
    join public.seasons s on s.id = st.season_id
    join public.teams t on t.id = st.team_id
    where s.league_id = p_league_id and t.manager_id = v_uid
  ) then
    return true;
  end if;

  -- Turnuvadaki bir takımın aktif oyuncusu (hesap e-postası <telefon>@...).
  v_raw := split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1);
  return exists (
    select 1 from public.season_team_players stp
    join public.seasons s on s.id = stp.season_id
    join public.players p on p.id = stp.player_id
    where s.league_id = p_league_id
      and coalesce(stp.is_active, true)
      and (p.auth_uid = v_uid
           or (v_raw <> '' and public.phone_raw10(p.phone) = v_raw))
  );
end;
$$;

-- Bölge sorumlusu davetleri (kurucu başkan / admin yönetir) --------------------

create or replace function public.link_region_owner_invites(p_raw10 text, p_uid uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_name text;
begin
  update public.region_owner_invites
  set user_id = p_uid
  where phone_raw10 = p_raw10 and user_id is distinct from p_uid;

  insert into public.region_owners (region_id, user_id)
  select region_id, p_uid from public.region_owner_invites
  where phone_raw10 = p_raw10
  on conflict do nothing;

  select full_name into v_name from public.region_owner_invites
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
revoke all on function public.link_region_owner_invites(text, uuid) from public, anon, authenticated;

create or replace function public.on_auth_user_created_link_region_owner()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := split_part(coalesce(new.email, ''), '@', 1);
begin
  if v_raw ~ '^5[0-9]{9}$' and exists (
    select 1 from public.region_owner_invites where phone_raw10 = v_raw
  ) then
    perform public.link_region_owner_invites(v_raw, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists link_region_owner_on_signup on auth.users;
create trigger link_region_owner_on_signup
  after insert on auth.users
  for each row execute function public.on_auth_user_created_link_region_owner();

create or replace function public.region_season(p_region_id uuid)
returns uuid
language sql
stable
security definer
set search_path to ''
as $$
  select season_id from public.season_regions where id = p_region_id
$$;

create or replace function public.list_region_owners(p_region_id uuid)
returns table (phone_raw10 text, full_name text, user_id uuid, has_account boolean)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if not public.owns_region(p_region_id) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  return query
    select i.phone_raw10, i.full_name, i.user_id, i.user_id is not null
    from public.region_owner_invites i
    where i.region_id = p_region_id
    order by i.full_name;
end;
$$;

create or replace function public.add_region_owner(
  p_region_id uuid,
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
  if not public.owns_season(public.region_season(p_region_id)) then
    raise exception 'Bölge sorumlusunu yalnızca turnuva sahibi ekleyebilir.'
      using errcode = '42501';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    raise exception 'Geçerli bir cep telefonu girin (5XX XXX XX XX).';
  end if;
  if v_name is null then
    raise exception 'Ad soyad girin.';
  end if;

  insert into public.region_owner_invites (region_id, phone_raw10, full_name)
  values (p_region_id, v_raw, left(v_name, 80))
  on conflict (region_id, phone_raw10) do update set full_name = excluded.full_name;

  v_uid := public.account_uid_for_phone(v_raw);
  if v_uid is null then
    return 'invited';
  end if;
  perform public.link_region_owner_invites(v_raw, v_uid);
  return 'linked';
end;
$$;

create or replace function public.remove_region_owner(p_region_id uuid, p_phone text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_uid uuid;
begin
  if not public.owns_season(public.region_season(p_region_id)) then
    raise exception 'Bölge sorumlusunu yalnızca turnuva sahibi kaldırabilir.'
      using errcode = '42501';
  end if;
  v_uid := public.account_uid_for_phone(v_raw);
  delete from public.region_owner_invites
  where region_id = p_region_id and phone_raw10 = v_raw;
  if v_uid is not null then
    delete from public.region_owners
    where region_id = p_region_id and user_id = v_uid;
  end if;
end;
$$;

revoke all on function public.list_region_owners(uuid) from public, anon;
revoke all on function public.add_region_owner(uuid, text, text) from public, anon;
revoke all on function public.remove_region_owner(uuid, text) from public, anon;
grant execute on function public.list_region_owners(uuid) to authenticated;
grant execute on function public.add_region_owner(uuid, text, text) to authenticated;
grant execute on function public.remove_region_owner(uuid, text) to authenticated;

-- Mevcut veri: Master Bosphorus Legends 2026-2027 iki bölgeye ayrılır.
insert into public.season_regions (season_id, name, city, sort_order)
select s.id, v.name, 'İstanbul', v.ord
from public.seasons s
join public.leagues l on l.id = s.league_id
cross join (values ('İstanbul (Avrupa)', 1), ('İstanbul (Anadolu)', 2)) v(name, ord)
where l.name = 'Master Bosphorus Legends' and s.name = '2026-2027 Sezonu'
on conflict (season_id, name) do nothing;

update public.groups g
set region_id = r.id
from public.season_regions r
where r.season_id = g.season_id
  and ((g.name = 'Avrupa Yakası' and r.name = 'İstanbul (Avrupa)')
    or (g.name = 'Anadolu Yakası' and r.name = 'İstanbul (Anadolu)'))
  and g.region_id is null;
