-- Kurucu başkan (turnuva sahibi) ve bölge sorumlusu yönetim paneli yetkileri.
--
-- * Takımlar: kurucu/bölge sorumlusu yeni takım ekleyebilir; mevcut takımı
--   yalnızca takım kendi turnuvasında (bölgesinde) oynuyorsa düzenler.
--   Silme admin'de kalır.
-- * Oyuncular: bölge sorumlusu da oyuncu ekleyip kendi bölgesindeki
--   oyuncuları düzenler.
-- * Haberler: isteğe bağlı bölge (news.region_id); bölge sorumlusu yalnızca
--   kendi bölgesine haber girer.

create or replace function public.is_any_region_owner()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (select 1 from public.region_owners where user_id = auth.uid())
$$;
grant execute on function public.is_any_region_owner() to authenticated;

-- Takımı yönetebilir mi: admin ya da takımın oynadığı bir sezonun
-- kurucusu / bölge sorumlusu.
create or replace function public.owns_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.is_admin() or exists (
    select 1 from public.season_teams st
    where st.team_id = p_team_id
      and public.owns_season_team(st.season_id, st.team_id)
  )
$$;
grant execute on function public.owns_team(uuid) to authenticated;

drop policy if exists teams_write on public.teams;
drop policy if exists teams_insert on public.teams;
drop policy if exists teams_update on public.teams;
drop policy if exists teams_delete on public.teams;
create policy teams_insert on public.teams for insert to authenticated
  with check (public.is_admin() or public.is_any_league_owner()
              or public.is_any_region_owner());
create policy teams_update on public.teams for update to authenticated
  using (public.owns_team(id)) with check (public.owns_team(id));
create policy teams_delete on public.teams for delete to authenticated
  using (public.is_admin());

-- Oyuncu: kurucu ya da oyuncunun takımının bölge sorumlusu.
create or replace function public.owns_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.is_admin() or exists (
    select 1 from public.season_team_players stp
    where stp.player_id = p_player_id
      and public.owns_season_team(stp.season_id, stp.team_id)
  )
$$;

drop policy if exists players_insert on public.players;
create policy players_insert on public.players for insert to authenticated
  with check (public.is_admin() or public.is_any_league_owner()
              or public.is_any_region_owner());

-- Haberler: isteğe bağlı bölge.
alter table public.news
  add column if not exists region_id uuid
  references public.season_regions (id) on delete set null;
create index if not exists news_region_idx on public.news (region_id);

-- Haberi yönetebilir mi: kurucu; bölgeli haberde o bölgenin sorumlusu da.
create or replace function public.owns_news(p_league_id uuid, p_region_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.owns_league(p_league_id) or (
    p_region_id is not null and exists (
      select 1 from public.season_regions r
      join public.seasons s on s.id = r.season_id
      join public.region_owners ro on ro.region_id = r.id
      where r.id = p_region_id and s.league_id = p_league_id
        and ro.user_id = auth.uid()
    )
  )
$$;
grant execute on function public.owns_news(uuid, uuid) to authenticated;

drop policy if exists news_write on public.news;
create policy news_write on public.news for all to authenticated
  using (public.owns_news(league_id, region_id))
  with check (public.owns_news(league_id, region_id));

drop policy if exists news_read on public.news;
create policy news_read on public.news for select
  using (public.owns_news(league_id, region_id)
         or (is_published
             and (publish_until is null or publish_until > now())
             and public.can_view_league(league_id)));

-- news kolon bazlı yetkili (like_count sunucuda); yeni kolon açılır.
grant select, insert (region_id), update (region_id) on public.news to authenticated;
grant select (region_id) on public.news to anon;
