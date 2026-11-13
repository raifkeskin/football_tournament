-- Faz 1 hız: sık birleştirilen / erişim kuralında aranan sütunlara indeks.
-- Tablolar bugün küçük; veri büyüdükçe birleştirme ve silmeler tam tarama
-- yapmasın diye şimdiden. CONCURRENTLY: canlıda tabloyu kilitlemez
-- (işlem bloğu dışında, psql ile tek tek çalıştırılmalı).

-- Hesap e-postasındaki telefonla futbolcu eşleştirme (rls_visible_league_ids).
create index concurrently if not exists players_phone_raw10_idx
  on public.players (public.phone_raw10(phone));

create index concurrently if not exists season_team_players_player_idx
  on public.season_team_players (player_id);
create index concurrently if not exists season_team_players_team_idx
  on public.season_team_players (team_id);

create index concurrently if not exists teams_manager_idx
  on public.teams (manager_id) where manager_id is not null;

create index concurrently if not exists match_events_player_idx
  on public.match_events (player_id);
create index concurrently if not exists match_events_team_idx
  on public.match_events (team_id);

create index concurrently if not exists match_rosters_team_idx
  on public.match_rosters (team_id);

create index concurrently if not exists matches_group_idx
  on public.matches (group_id);

create index concurrently if not exists team_managers_team_idx
  on public.team_managers (team_id);

create index concurrently if not exists player_penalties_season_idx
  on public.player_penalties (season_id);

create index concurrently if not exists season_registrations_season_idx
  on public.season_registrations (season_id);
