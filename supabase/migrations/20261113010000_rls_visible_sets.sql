-- Faz 1 hız: erişim kurallarında "bu turnuvayı/sezonu/maçı görebilir mi"
-- kontrolü her satırda ayrı ayrı çalışıyordu (gizli turnuvada satır başına
-- ~0,6 ms). Artık görünür turnuva/sezon/maç kümesi sorgu başına BİR KEZ
-- hesaplanır, satırlar bu kümeyle (hash) karşılaştırılır. Kural aynıdır:
-- rls_visible_league_ids() = { l | can_view_league(l) } (98 kullanıcı + misafir
-- için tablo tablo eşitlik testiyle doğrulandı). Rol/sahiplik değişikliği
-- bir sonraki istekte geçerlidir (oturum başına önbellek yok).
--
-- Ayrıca auth.uid() / is_admin() çağrıları ( SELECT ... ) içine alındı:
-- satır başına değil sorgu başına bir kez çalışır (Supabase önerisi).
-- Yalnız SELECT/ALL kuralları değişti; yazma kuralları aynı.

-- Basit ayar okuma (app_settings herkese açık; kural içinde tek sefer).
create or replace function public.app_flag(p_key text)
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select coalesce((
    select s.value = 'true'::jsonb from public.app_settings s where s.key = p_key
  ), false)
$$;

-- Giriş yapanın (ya da misafirin) görebildiği turnuvalar.
-- can_view_league ile birebir aynı kural; değişirse ikisi birlikte değişmeli.
create or replace function public.rls_visible_league_ids()
returns setof uuid
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text;
  v_players uuid[];
begin
  -- Pasif turnuva kimseye görünmez (admin dahil).
  if not public.private_leagues_enabled() then
    return query
      select l.id from public.leagues l
       where not (coalesce(l.status, '') = 'passive' or l.is_active is false);
    return;
  end if;

  return query
    select l.id from public.leagues l
     where not (coalesce(l.status, '') = 'passive' or l.is_active is false)
       and not coalesce(l.is_private, false);

  if v_uid is null then
    return;
  end if;

  if public.is_admin() then
    return query
      select l.id from public.leagues l
       where not (coalesce(l.status, '') = 'passive' or l.is_active is false)
         and coalesce(l.is_private, false);
    return;
  end if;

  -- Hesabın futbolcu kayıtları (hesap e-postası <telefon>@...).
  v_raw := split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1);
  select coalesce(array_agg(p.id), '{}') into v_players
    from public.players p
   where p.auth_uid = v_uid
      or (v_raw <> '' and public.phone_raw10(p.phone) = v_raw);

  return query
    select l.id from public.leagues l
     where not (coalesce(l.status, '') = 'passive' or l.is_active is false)
       and coalesce(l.is_private, false)
       and (
         exists (select 1 from public.league_owners o
                  where o.league_id = l.id and o.user_id = v_uid)
         or exists (select 1 from public.region_owners ro
                      join public.season_regions r on r.id = ro.region_id
                      join public.seasons s on s.id = r.season_id
                     where s.league_id = l.id and ro.user_id = v_uid)
         or exists (select 1 from public.league_followers f
                     where f.league_id = l.id and f.user_id = v_uid
                       and lower(f.code) = lower(coalesce(l.access_code, '')))
         or exists (select 1 from public.matches m
                     where m.league_id = l.id and m.observer_id = v_uid)
         or exists (select 1 from public.team_managers tm
                      join public.seasons s on s.id = tm.season_id
                     where s.league_id = l.id and tm.user_id = v_uid)
         or exists (select 1 from public.season_teams st
                      join public.seasons s on s.id = st.season_id
                      join public.teams t on t.id = st.team_id
                     where s.league_id = l.id and t.manager_id = v_uid)
         or exists (select 1 from public.season_team_players stp
                      join public.seasons s on s.id = stp.season_id
                     where s.league_id = l.id
                       and coalesce(stp.is_active, true)
                       and stp.player_id = any (v_players))
       );
end;
$$;

-- can_view_season ile aynı: silinmemiş ve turnuvası görünür (turnuvasız da görünür).
create or replace function public.rls_visible_season_ids()
returns setof uuid
language sql
stable security definer
set search_path to ''
as $$
  select s.id from public.seasons s
   where s.deleted_at is null
     and (s.league_id is null
          or s.league_id in (select public.rls_visible_league_ids()))
$$;

-- can_view_match ile aynı: silinmemiş ve turnuvası (yoksa sezonunun turnuvası) görünür.
create or replace function public.rls_visible_match_ids()
returns setof uuid
language sql
stable security definer
set search_path to ''
as $$
  select m.id from public.matches m
    left join public.seasons s on s.id = m.season_id
   where m.deleted_at is null
     and (coalesce(m.league_id, s.league_id) is null
          or coalesce(m.league_id, s.league_id)
             in (select public.rls_visible_league_ids()))
$$;

-- owns_season'ın admin dışı kısmı: turnuva sahibi olunan sezonlar.
create or replace function public.rls_owned_season_ids()
returns setof uuid
language sql
stable security definer
set search_path to ''
as $$
  select s.id from public.seasons s
    join public.league_owners o on o.league_id = s.league_id
   where o.user_id = auth.uid()
$$;

-- Bölge sorumlusu olunan (bölge, sezon) çiftleri (owns_news'in bölge kısmı).
create or replace function public.rls_owned_region_pairs()
returns table (region_id uuid, season_id uuid)
language sql
stable security definer
set search_path to ''
as $$
  select r.id, r.season_id from public.season_regions r
    join public.region_owners ro on ro.region_id = r.id
   where ro.user_id = auth.uid()
$$;

revoke all on function public.app_flag(text) from public;
revoke all on function public.rls_visible_league_ids() from public;
revoke all on function public.rls_visible_season_ids() from public;
revoke all on function public.rls_visible_match_ids() from public;
revoke all on function public.rls_owned_season_ids() from public;
revoke all on function public.rls_owned_region_pairs() from public;
grant execute on function public.app_flag(text) to anon, authenticated, service_role;
grant execute on function public.rls_visible_league_ids() to anon, authenticated, service_role;
grant execute on function public.rls_visible_season_ids() to anon, authenticated, service_role;
grant execute on function public.rls_visible_match_ids() to anon, authenticated, service_role;
grant execute on function public.rls_owned_season_ids() to anon, authenticated, service_role;
grant execute on function public.rls_owned_region_pairs() to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Kurallar (yalnız SELECT/ALL; USING). Üretici: eski metin -> küme / ( SELECT ...).
-- ---------------------------------------------------------------------------
alter policy account_requests_admin on public.account_requests
  using (( SELECT public.is_admin()));

alter policy admins_read on public.admins
  using (((user_id = ( SELECT auth.uid())) OR ( SELECT public.is_admin())));

alter policy admins_write on public.admins
  using (( SELECT public.is_admin()));

alter policy ai_usage_log_admin_read on public.ai_usage_log
  using (( SELECT public.is_admin()));

alter policy app_errors_admin_read on public.app_errors
  using (( SELECT public.is_admin()));

alter policy app_users_admin on public.app_users
  using (( SELECT public.is_admin()));

alter policy app_users_own on public.app_users
  using (((auth_uid = (( SELECT auth.uid()))::text) OR ( SELECT public.is_admin())));

alter policy awards_read on public.awards
  using (((league_id IS NULL) OR (league_id IN ( SELECT public.rls_visible_league_ids()))));

alter policy cup_brackets_select on public.cup_brackets
  using (((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids()))));

alter policy fan_members_read_own on public.fan_members
  using (((user_id = ( SELECT auth.uid())) OR ( SELECT public.is_admin())));

alter policy followed_leagues_own on public.followed_leagues
  using ((user_id = ( SELECT auth.uid())));

alter policy followed_teams_own on public.followed_teams
  using ((user_id = ( SELECT auth.uid())));

alter policy groups_read on public.groups
  using (((deleted_at IS NULL) AND ((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids())))));

alter policy league_followers_own on public.league_followers
  using (((user_id = ( SELECT auth.uid())) OR owns_league(league_id)));

alter policy lmc_read on public.league_media_credits
  using (((league_id IS NULL) OR (league_id IN ( SELECT public.rls_visible_league_ids()))));

alter policy league_owner_invites_admin on public.league_owner_invites
  using (( SELECT public.is_admin()));

alter policy league_owners_read on public.league_owners
  using (((user_id = ( SELECT auth.uid())) OR ( SELECT public.is_admin())));

alter policy league_owners_write on public.league_owners
  using (( SELECT public.is_admin()));

alter policy league_referees_read on public.league_referees
  using (((league_id IS NULL) OR (league_id IN ( SELECT public.rls_visible_league_ids()))));

alter policy leagues_read on public.leagues
  using (((NOT is_private) OR ((id IS NULL) OR (id IN ( SELECT public.rls_visible_league_ids()))) OR owns_league(id)));

alter policy match_events_read on public.match_events
  using (((match_id IS NULL) OR (match_id IN ( SELECT public.rls_visible_match_ids()))));

alter policy match_highlights_select on public.match_highlights
  using ((((status = 'approved'::text) AND ((match_id IS NULL) OR (match_id IN ( SELECT public.rls_visible_match_ids())))) OR owns_match(match_id)));

alter policy match_media_read on public.match_media
  using (((match_id IS NULL) OR (match_id IN ( SELECT public.rls_visible_match_ids()))));

alter policy match_media_crew_read on public.match_media_crew
  using (((match_id IS NULL) OR (match_id IN ( SELECT public.rls_visible_match_ids()))));

alter policy match_moments_read on public.match_moments
  using (((match_id IS NULL) OR (match_id IN ( SELECT public.rls_visible_match_ids()))));

alter policy match_predictions_read on public.match_predictions
  using ((user_id = ( SELECT auth.uid())));

alter policy match_rosters_read on public.match_rosters
  using (((match_id IS NULL) OR (match_id IN ( SELECT public.rls_visible_match_ids()))));

alter policy matches_read on public.matches
  using (((deleted_at IS NULL) AND ((league_id IN ( SELECT public.rls_visible_league_ids())) OR ((league_id IS NULL) AND can_view_league(( SELECT s.league_id FROM seasons s WHERE (s.id = matches.season_id)))))));

alter policy news_read on public.news
  using ((((auto_kind IS NULL) OR (auto_kind <> ALL (ARRAY['interviews'::text, 'video'::text])) OR ( SELECT public.app_flag('video_news_public'::text)) OR ( SELECT public.is_admin()) OR (season_id IN ( SELECT public.rls_owned_season_ids()))) AND (( SELECT public.is_admin()) OR (season_id IN ( SELECT public.rls_owned_season_ids())) OR ((region_id IS NOT NULL) AND ((region_id, season_id) IN ( SELECT r.region_id, r.season_id FROM public.rls_owned_region_pairs() r))) OR (is_published AND ((publish_until IS NULL) OR (publish_until > now())) AND ((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids())))))));

alter policy news_comment_blocks_read on public.news_comment_blocks
  using ((user_id = ( SELECT auth.uid())));

alter policy news_comment_terms_read on public.news_comment_terms
  using ((user_id = ( SELECT auth.uid())));

alter policy news_comments_read on public.news_comments
  using ((((status = 'published'::text) AND (EXISTS ( SELECT 1
   FROM news n
  WHERE (n.id = news_comments.news_id)))) OR (user_id = ( SELECT auth.uid())) OR (EXISTS ( SELECT 1
   FROM news n
  WHERE ((n.id = news_comments.news_id) AND owns_news(n.season_id, n.region_id))))));

alter policy news_likes_read on public.news_likes
  using ((user_id = ( SELECT auth.uid())));

alter policy news_reactions_read on public.news_reactions
  using ((user_id = ( SELECT auth.uid())));

alter policy notification_prefs_own on public.notification_prefs
  using ((user_id = ( SELECT auth.uid())));

alter policy notifications_own_read on public.notifications
  using ((user_id = ( SELECT auth.uid())));

alter policy otp_codes_admin on public.otp_codes
  using (( SELECT public.is_admin()));

alter policy pending_actions_read on public.pending_actions
  using (((submitted_by = ( SELECT auth.uid())) OR owns_league(league_id) OR owns_season_team(season_id, team_id)));

alter policy player_consents_read on public.player_consents
  using ((( SELECT public.is_admin()) OR (EXISTS ( SELECT 1
   FROM players p
  WHERE ((p.id = player_consents.player_id) AND (p.auth_uid = ( SELECT auth.uid())))))));

alter policy player_penalties_read on public.player_penalties
  using (((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids()))));

alter policy player_photo_cutout_skips_admin on public.player_photo_cutout_skips
  using (( SELECT public.is_admin()));

alter policy player_photo_cutouts_admin on public.player_photo_cutouts
  using (( SELECT public.is_admin()));

alter policy player_photo_stars_select on public.player_photo_stars
  using ((player_photos_public(player_id) OR (player_id IN ( SELECT p.id
   FROM players p
  WHERE (p.auth_uid = ( SELECT auth.uid())))) OR ( SELECT public.is_admin()) OR ( SELECT public.is_any_league_owner()) OR ( SELECT public.is_any_region_owner())));

alter policy player_season_declarations_read on public.player_season_declarations
  using ((( SELECT public.is_admin()) OR (EXISTS ( SELECT 1
   FROM players p
  WHERE ((p.id = player_season_declarations.player_id) AND (p.auth_uid = ( SELECT auth.uid())))))));

alter policy player_season_stats_read on public.player_season_stats
  using (((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids()))));

alter policy profile_change_requests_read on public.profile_change_requests
  using (((requested_by = ( SELECT auth.uid())) OR owns_player(player_id)));

alter policy push_subscriptions_own on public.push_subscriptions
  using ((user_id = ( SELECT auth.uid())));

alter policy region_owners_read on public.region_owners
  using (((user_id = ( SELECT auth.uid())) OR owns_region(region_id)));

alter policy season_regions_read on public.season_regions
  using (((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids()))));

alter policy season_registrations_read on public.season_registrations
  using (((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids()))));

alter policy season_team_players_read on public.season_team_players
  using (((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids()))));

alter policy season_teams_read on public.season_teams
  using (((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids()))));

alter policy seasons_read on public.seasons
  using (((deleted_at IS NULL) AND ((league_id IS NULL) OR (league_id IN ( SELECT public.rls_visible_league_ids())))));

alter policy sponsors_read on public.sponsors
  using (((league_id IS NULL) OR (league_id IN ( SELECT public.rls_visible_league_ids()))));

alter policy team_managers_read on public.team_managers
  using (((user_id = ( SELECT auth.uid())) OR owns_season_team(season_id, team_id)));

alter policy tournament_offers_admin on public.tournament_offers
  using (( SELECT public.is_admin()));

alter policy tournament_requests_read on public.tournament_requests
  using (((user_id = ( SELECT auth.uid())) OR ( SELECT public.is_admin())));

alter policy user_follows_own on public.user_follows
  using ((user_id = ( SELECT auth.uid())));

alter policy video_players_read on public.video_players
  using ((EXISTS ( SELECT 1
   FROM videos v
  WHERE ((v.id = video_players.video_id) AND ((v.season_id IS NULL) OR (v.season_id IN ( SELECT public.rls_visible_season_ids())))))));

alter policy videos_read on public.videos
  using (((season_id IS NULL) OR (season_id IN ( SELECT public.rls_visible_season_ids()))));
