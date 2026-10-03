-- Gizli turnuvalar.
--
-- Gizli (is_private) turnuvanın verisini yalnızca şunlar okur:
--   admin, turnuva sahipleri, maç gözlemcileri, turnuvadaki takımların
--   sorumluları ve aktif oyuncuları, erişim kodunu girmiş takipçiler.
-- Takipçi kaydı (league_followers) girilen kodu da saklar; turnuvanın kodu
-- değişince eski kodla takip edenlerin erişimi kendiliğinden kapanır.
-- Giriş yapmamış takipçiler uygulamada isimsiz (anonymous) oturumla gelir.

create table if not exists public.league_followers (
  league_id  uuid not null references public.leagues (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  code       text not null,
  created_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
create index if not exists league_followers_user_idx on public.league_followers (user_id);

alter table public.league_followers enable row level security;
drop policy if exists league_followers_own on public.league_followers;
create policy league_followers_own on public.league_followers
  for select to authenticated
  using (user_id = auth.uid() or public.owns_league(league_id));

-- Turnuvayı görebilir mi? (RLS'te satır başına çağrılır.)
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
  if not exists (
    select 1 from public.leagues where id = p_league_id and is_private
  ) then
    return true;
  end if;
  if v_uid is null then
    return false;
  end if;
  if public.owns_league(p_league_id) then
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

create or replace function public.can_view_season(p_season_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.can_view_league(
    (select league_id from public.seasons where id = p_season_id)
  );
$$;

create or replace function public.can_view_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.can_view_league((
    select coalesce(m.league_id, s.league_id)
    from public.matches m
    left join public.seasons s on s.id = m.season_id
    where m.id = p_match_id
  ));
$$;

grant execute on function public.can_view_league(uuid) to anon, authenticated;
grant execute on function public.can_view_season(uuid) to anon, authenticated;
grant execute on function public.can_view_match(uuid) to anon, authenticated;

-- Okuma kuralları -------------------------------------------------------------
drop policy if exists leagues_read on public.leagues;
create policy leagues_read on public.leagues for select
  using (not is_private or public.can_view_league(id));

drop policy if exists seasons_read on public.seasons;
create policy seasons_read on public.seasons for select
  using (public.can_view_league(league_id));

drop policy if exists groups_read on public.groups;
create policy groups_read on public.groups for select
  using (public.can_view_season(season_id));

drop policy if exists season_teams_read on public.season_teams;
create policy season_teams_read on public.season_teams for select
  using (public.can_view_season(season_id));

drop policy if exists season_registrations_read on public.season_registrations;
create policy season_registrations_read on public.season_registrations for select
  using (public.can_view_season(season_id));

drop policy if exists season_team_players_read on public.season_team_players;
create policy season_team_players_read on public.season_team_players for select
  using (public.can_view_season(season_id));

drop policy if exists player_season_stats_read on public.player_season_stats;
create policy player_season_stats_read on public.player_season_stats for select
  using (public.can_view_season(season_id));

drop policy if exists player_penalties_read on public.player_penalties;
create policy player_penalties_read on public.player_penalties for select
  using (public.can_view_season(season_id));

drop policy if exists matches_read on public.matches;
create policy matches_read on public.matches for select
  using (public.can_view_league(coalesce(
    league_id,
    (select s.league_id from public.seasons s where s.id = matches.season_id)
  )));

drop policy if exists match_events_read on public.match_events;
create policy match_events_read on public.match_events for select
  using (public.can_view_match(match_id));

drop policy if exists match_rosters_read on public.match_rosters;
create policy match_rosters_read on public.match_rosters for select
  using (public.can_view_match(match_id));

drop policy if exists match_media_read on public.match_media;
create policy match_media_read on public.match_media for select
  using (public.can_view_match(match_id));

drop policy if exists awards_read on public.awards;
create policy awards_read on public.awards for select
  using (public.can_view_league(league_id));

drop policy if exists news_read on public.news;
create policy news_read on public.news for select
  using (
    public.owns_league(league_id)
    or (is_published
        and (publish_until is null or publish_until > now())
        and public.can_view_league(league_id))
  );

-- Kod işlemleri ---------------------------------------------------------------

-- Kodu girilen turnuvayı takip et. Döner: {league_id, name}; kod yanlışsa hata.
create or replace function public.follow_league_by_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := lower(trim(coalesce(p_code, '')));
  l public.leagues%rowtype;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '42501';
  end if;
  if v_code = '' then
    raise exception 'Kodu girin.';
  end if;

  select * into l from public.leagues
  where lower(coalesce(access_code, '')) = v_code and is_active
  limit 1;
  if not found then
    raise exception 'Kod hatalı. Turnuva sorumlusundan kodu kontrol edin.'
      using errcode = 'P0002';
  end if;

  insert into public.league_followers (league_id, user_id, code)
  values (l.id, v_uid, l.access_code)
  on conflict (league_id, user_id) do update
    set code = excluded.code, created_at = now();

  return jsonb_build_object('league_id', l.id, 'name', l.name);
end;
$$;

-- Yeni kod üretir; eski kodla takip edenlerin erişimi kapanır.
create or replace function public.regenerate_league_code(p_league_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_code text;
begin
  if not public.owns_league(p_league_id) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  loop
    v_code := lpad(((random() * 900000)::int + 100000)::text, 6, '0');
    exit when not exists (
      select 1 from public.leagues where access_code = v_code
    );
  end loop;
  update public.leagues set access_code = v_code where id = p_league_id;
  delete from public.league_followers where league_id = p_league_id;
  return v_code;
end;
$$;

revoke all on function public.follow_league_by_code(text) from public, anon;
revoke all on function public.regenerate_league_code(uuid) from public, anon;
grant execute on function public.follow_league_by_code(text) to authenticated;
grant execute on function public.regenerate_league_code(uuid) to authenticated;
