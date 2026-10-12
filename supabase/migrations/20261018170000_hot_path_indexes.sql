-- Sık okunan filtreler için eksik indexler (yük testi sonrası, 2026-10-11).
-- Ekranlar maçları / olayları / kadroları sezona ya da maça göre süzer;
-- bu sütunlarda index yoktu (tablolar küçükken fark edilmiyordu).
create index if not exists matches_season_idx on public.matches (season_id);
create index if not exists matches_league_idx on public.matches (league_id);
create index if not exists matches_home_team_idx on public.matches (home_team_id);
create index if not exists matches_away_team_idx on public.matches (away_team_id);
create index if not exists match_events_match_idx on public.match_events (match_id);
create index if not exists match_events_season_idx on public.match_events (season_id);
create index if not exists match_rosters_season_idx on public.match_rosters (season_id);
create index if not exists match_media_match_idx on public.match_media (match_id);
create index if not exists groups_season_idx on public.groups (season_id);
create index if not exists player_season_stats_season_idx
  on public.player_season_stats (season_id);
