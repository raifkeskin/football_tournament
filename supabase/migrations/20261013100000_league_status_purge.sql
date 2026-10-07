-- Turnuva yumuşak silme ve kalıcı temizleme.
-- status = 'deleted' olan turnuva hiç kimseye görünmez (can_view_league false).
-- admin_purge_league yalnızca silinmiş turnuvayı, futbolcu kayıtlarına dokunmadan temizler.

alter table public.leagues
  add column if not exists status text not null default 'active'
    check (status in ('active', 'deleted'));

drop policy if exists leagues_read on public.leagues;
create policy leagues_read on public.leagues for select
  using (status = 'active' and (not is_private or public.can_view_league(id)));

create or replace function public.can_view_league(p_league_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text;
begin
  if p_league_id is null then
    return true;
  end if;
  if exists (
    select 1 from public.leagues where id = p_league_id and status = 'deleted'
  ) then
    return false;
  end if;
  -- Demo turnuva her zaman gizlidir; diğerleri özellik açıksa ve gizliyse.
  if not exists (
    select 1 from public.leagues where id = p_league_id and is_demo
  ) then
    if not public.private_leagues_enabled() then
      return true;
    end if;
    if not exists (
      select 1 from public.leagues where id = p_league_id and is_private
    ) then
      return true;
    end if;
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

create or replace function public.admin_delete_league(p_league_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yetkisiz';
  end if;
  update public.leagues set status = 'deleted' where id = p_league_id;
end;
$$;

-- p_dry_run = true: silinecek satır sayılarını döndürür, hiçbir şey silmez.
create or replace function public.admin_purge_league(p_league_id uuid, p_dry_run boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seasons uuid[];
  v_teams uuid[];
  v_regions uuid[];
  v_news uuid[];
  v_matches uuid[];
  v_counts jsonb;
begin
  if not public.is_admin() then
    raise exception 'Yetkisiz';
  end if;
  if not exists (
    select 1 from public.leagues where id = p_league_id and status = 'deleted'
  ) then
    raise exception 'Turnuva önce silinmiş olmalı (status = deleted)';
  end if;

  select coalesce(array_agg(id), '{}') into v_seasons
    from public.seasons where league_id = p_league_id;
  select coalesce(array_agg(id), '{}') into v_regions
    from public.season_regions where season_id = any(v_seasons);
  select coalesce(array_agg(id), '{}') into v_news
    from public.news where league_id = p_league_id;
  select coalesce(array_agg(id), '{}') into v_matches
    from public.matches where league_id = p_league_id;

  -- Yalnızca bu turnuvanın sezonlarında geçen takımlar; başka yerde kullanılanlar kalır.
  select coalesce(array_agg(distinct st.team_id), '{}') into v_teams
    from public.season_teams st
    where st.season_id = any(v_seasons)
      and not exists (
        select 1 from public.season_teams o
        where o.team_id = st.team_id and o.season_id <> all(v_seasons))
      and not exists (
        select 1 from public.season_registrations r
        where r.team_id = st.team_id and r.season_id <> all(v_seasons))
      and not exists (
        select 1 from public.matches m
        where (m.home_team_id = st.team_id or m.away_team_id = st.team_id)
          and m.season_id <> all(v_seasons))
      and not exists (
        select 1 from public.team_managers tm
        where tm.team_id = st.team_id and tm.season_id <> all(v_seasons));

  v_counts := jsonb_build_object(
    'seasons', (select count(*) from public.seasons where id = any(v_seasons)),
    'groups', (select count(*) from public.groups where season_id = any(v_seasons)),
    'season_regions', (select count(*) from public.season_regions where id = any(v_regions)),
    'region_owners', (select count(*) from public.region_owners where region_id = any(v_regions)),
    'region_owner_invites', (select count(*) from public.region_owner_invites where region_id = any(v_regions)),
    'season_teams', (select count(*) from public.season_teams where season_id = any(v_seasons)),
    'season_team_players', (select count(*) from public.season_team_players where season_id = any(v_seasons)),
    'season_registrations', (select count(*) from public.season_registrations where season_id = any(v_seasons)),
    'team_managers', (select count(*) from public.team_managers where season_id = any(v_seasons)),
    'player_season_stats', (select count(*) from public.player_season_stats where season_id = any(v_seasons)),
    'player_penalties', (select count(*) from public.player_penalties where season_id = any(v_seasons)),
    'matches', (select count(*) from public.matches where id = any(v_matches)),
    'match_rosters', (select count(*) from public.match_rosters where match_id = any(v_matches)),
    'match_events', (select count(*) from public.match_events where match_id = any(v_matches)),
    'match_media', (select count(*) from public.match_media where match_id = any(v_matches)),
    'live_draws', (select count(*) from public.live_draws where league_id = p_league_id),
    'news', (select count(*) from public.news where id = any(v_news)),
    'news_likes', (select count(*) from public.news_likes where news_id = any(v_news)),
    'awards', (select count(*) from public.awards where league_id = p_league_id),
    'sponsors', (select count(*) from public.sponsors where league_id = p_league_id),
    'league_owners', (select count(*) from public.league_owners where league_id = p_league_id),
    'league_owner_invites', (select count(*) from public.league_owner_invites where league_id = p_league_id),
    'league_followers', (select count(*) from public.league_followers where league_id = p_league_id),
    'pending_actions', (select count(*) from public.pending_actions where league_id = p_league_id),
    'teams', cardinality(v_teams)
  );

  if p_dry_run then
    return jsonb_build_object('dry_run', true, 'counts', v_counts);
  end if;

  delete from public.matches where id = any(v_matches);
  delete from public.seasons where id = any(v_seasons);
  delete from public.teams where id = any(v_teams);
  delete from public.leagues where id = p_league_id;

  return jsonb_build_object('dry_run', false, 'counts', v_counts);
end;
$$;

revoke all on function public.admin_delete_league(uuid) from public, anon;
revoke all on function public.admin_purge_league(uuid, boolean) from public, anon;
grant execute on function public.admin_delete_league(uuid) to authenticated;
grant execute on function public.admin_purge_league(uuid, boolean) to authenticated;
