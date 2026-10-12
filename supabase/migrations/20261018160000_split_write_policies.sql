-- Yazma politikalarını okumadan ayır (performans).
--
-- FOR ALL politikaları SELECT'te de değerlendirilir: okuma politikasıyla
-- OR'lanır ve sahiplik fonksiyonu (owns_season_team vb.) her satır için
-- çalışır. Yük testinde season_team_players okuması bu yüzden 155 ms
-- sürüyordu; yazma politikası yalnız yazmaya uygulanınca 15 ms.
--
-- Okuma yetkisi değişmez: bu tablolarda okuma politikası (can_view_*) zaten
-- turnuva sahiplerini ve bölge sorumlularını kapsar. Yazma kuralları aynen
-- korunur; yalnızca INSERT / UPDATE / DELETE olarak üçe bölünür.
-- Okuma yolu FOR ALL olan tablolara (account_requests, otp_codes,
-- followed_*, notification_prefs, admins, app_users, league_*) dokunulmaz.

drop policy app_settings_admin_write on public.app_settings;
create policy app_settings_insert on public.app_settings for insert to authenticated
  with check (is_admin());
create policy app_settings_update on public.app_settings for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy app_settings_delete on public.app_settings for delete to authenticated
  using (is_admin());

drop policy awards_write on public.awards;
create policy awards_insert on public.awards for insert to authenticated
  with check (owns_league(league_id));
create policy awards_update on public.awards for update to authenticated
  using (owns_league(league_id))
  with check (owns_league(league_id));
create policy awards_delete on public.awards for delete to authenticated
  using (owns_league(league_id));

drop policy match_events_write on public.match_events;
create policy match_events_insert on public.match_events for insert to authenticated
  with check (can_manage_match(match_id));
create policy match_events_update on public.match_events for update to authenticated
  using (can_manage_match(match_id))
  with check (can_manage_match(match_id));
create policy match_events_delete on public.match_events for delete to authenticated
  using (can_manage_match(match_id));

drop policy match_media_write on public.match_media;
create policy match_media_insert on public.match_media for insert to authenticated
  with check (owns_match(match_id));
create policy match_media_update on public.match_media for update to authenticated
  using (owns_match(match_id))
  with check (owns_match(match_id));
create policy match_media_delete on public.match_media for delete to authenticated
  using (owns_match(match_id));

drop policy match_rosters_write on public.match_rosters;
create policy match_rosters_insert on public.match_rosters for insert to authenticated
  with check ((owns_league(league_id) OR can_edit_match_roster(match_id, team_id)));
create policy match_rosters_update on public.match_rosters for update to authenticated
  using ((owns_league(league_id) OR can_edit_match_roster(match_id, team_id)))
  with check ((owns_league(league_id) OR can_edit_match_roster(match_id, team_id)));
create policy match_rosters_delete on public.match_rosters for delete to authenticated
  using ((owns_league(league_id) OR can_edit_match_roster(match_id, team_id)));

drop policy matches_write on public.matches;
create policy matches_insert on public.matches for insert to authenticated
  with check ((owns_league(COALESCE(league_id, ( SELECT s.league_id
   FROM seasons s
  WHERE (s.id = matches.season_id)))) OR owns_group(group_id)));
create policy matches_update on public.matches for update to authenticated
  using ((owns_league(COALESCE(league_id, ( SELECT s.league_id
   FROM seasons s
  WHERE (s.id = matches.season_id)))) OR owns_group(group_id)))
  with check ((owns_league(COALESCE(league_id, ( SELECT s.league_id
   FROM seasons s
  WHERE (s.id = matches.season_id)))) OR owns_group(group_id)));
create policy matches_delete on public.matches for delete to authenticated
  using ((owns_league(COALESCE(league_id, ( SELECT s.league_id
   FROM seasons s
  WHERE (s.id = matches.season_id)))) OR owns_group(group_id)));

drop policy news_write on public.news;
create policy news_insert on public.news for insert to authenticated
  with check (owns_news(season_id, region_id));
create policy news_update on public.news for update to authenticated
  using (owns_news(season_id, region_id))
  with check (owns_news(season_id, region_id));
create policy news_delete on public.news for delete to authenticated
  using (owns_news(season_id, region_id));

drop policy pitches_write on public.pitches;
create policy pitches_insert on public.pitches for insert to authenticated
  with check (is_admin());
create policy pitches_update on public.pitches for update to authenticated
  using (is_admin())
  with check (is_admin());
create policy pitches_delete on public.pitches for delete to authenticated
  using (is_admin());

drop policy player_penalties_write on public.player_penalties;
create policy player_penalties_insert on public.player_penalties for insert to authenticated
  with check (owns_season_player(season_id, player_id));
create policy player_penalties_update on public.player_penalties for update to authenticated
  using (owns_season_player(season_id, player_id))
  with check (owns_season_player(season_id, player_id));
create policy player_penalties_delete on public.player_penalties for delete to authenticated
  using (owns_season_player(season_id, player_id));

drop policy player_season_stats_write on public.player_season_stats;
create policy player_season_stats_insert on public.player_season_stats for insert to authenticated
  with check (owns_season_player(season_id, player_id));
create policy player_season_stats_update on public.player_season_stats for update to authenticated
  using (owns_season_player(season_id, player_id))
  with check (owns_season_player(season_id, player_id));
create policy player_season_stats_delete on public.player_season_stats for delete to authenticated
  using (owns_season_player(season_id, player_id));

drop policy season_regions_write on public.season_regions;
create policy season_regions_insert on public.season_regions for insert to authenticated
  with check (owns_season(season_id));
create policy season_regions_update on public.season_regions for update to authenticated
  using (owns_season(season_id))
  with check (owns_season(season_id));
create policy season_regions_delete on public.season_regions for delete to authenticated
  using (owns_season(season_id));

drop policy season_registrations_write on public.season_registrations;
create policy season_registrations_insert on public.season_registrations for insert to authenticated
  with check ((owns_season(season_id) OR owns_group(group_id)));
create policy season_registrations_update on public.season_registrations for update to authenticated
  using ((owns_season(season_id) OR owns_group(group_id)))
  with check ((owns_season(season_id) OR owns_group(group_id)));
create policy season_registrations_delete on public.season_registrations for delete to authenticated
  using ((owns_season(season_id) OR owns_group(group_id)));

drop policy season_team_players_write on public.season_team_players;
create policy season_team_players_insert on public.season_team_players for insert to authenticated
  with check (owns_season_team(season_id, team_id));
create policy season_team_players_update on public.season_team_players for update to authenticated
  using (owns_season_team(season_id, team_id))
  with check (owns_season_team(season_id, team_id));
create policy season_team_players_delete on public.season_team_players for delete to authenticated
  using (owns_season_team(season_id, team_id));

drop policy season_teams_write on public.season_teams;
create policy season_teams_insert on public.season_teams for insert to authenticated
  with check ((owns_season(season_id) OR owns_group(group_id)));
create policy season_teams_update on public.season_teams for update to authenticated
  using ((owns_season(season_id) OR owns_group(group_id)))
  with check ((owns_season(season_id) OR owns_group(group_id)));
create policy season_teams_delete on public.season_teams for delete to authenticated
  using ((owns_season(season_id) OR owns_group(group_id)));

drop policy team_managers_write on public.team_managers;
create policy team_managers_insert on public.team_managers for insert to authenticated
  with check (owns_season_team(season_id, team_id));
create policy team_managers_update on public.team_managers for update to authenticated
  using (owns_season_team(season_id, team_id))
  with check (owns_season_team(season_id, team_id));
create policy team_managers_delete on public.team_managers for delete to authenticated
  using (owns_season_team(season_id, team_id));

