-- ============================================================================
-- match_rosters / season_team_players indeks düzenlemesi
--
-- Mevcut durum ve kod içindeki sorgular incelendi:
--
-- match_rosters
--   (match_id, player_id) UNIQUE  → match_id ile yapılan tüm sorguları karşılar
--                                    (kadro ekranı: match_id [+ team_id]).
--   EKSİK: sadece player_id ile sorgu var (player_card.dart: oyuncunun
--          oynadığı maçlar). Başta match_id olduğu için mevcut indeks bunu
--          karşılamaz → tablo taraması. Aşağıda eklenir.
--
-- season_team_players
--   (season_id, team_id, player_id) UNIQUE → takım+sezon kadro sorguları
--   (player_id, season_id) UNIQUE         → oyuncunun sezon kaydı sorguları
--   Koddaki tüm sorgular bu ikisiyle karşılanıyor; ekleme/çıkarma gerekmez.
--   (Pkey adının hâlâ "league_team_players_pkey" olması yalnızca isimdir,
--   performansa etkisi yoktur.)
--
-- Silinecek indeks yok: mevcut indekslerin hepsi UNIQUE kısıt ya da birincil
-- anahtar; veri bütünlüğünü koruyorlar.
--
-- Supabase SQL Editor'da tek seferde çalıştırın. Tekrar çalıştırılması
-- güvenlidir (IF NOT EXISTS).
--
-- Not: SQL Editor scripti bir transaction içinde çalıştırdığı için
-- CONCURRENTLY kullanılamaz. Tablolar küçükken normal CREATE INDEX'in
-- kilidi milisaniyeler sürer. Tablolar çok büyüdüğünde indeks eklemek
-- gerekirse, CONCURRENTLY'li komutu tek başına (başka komut olmadan)
-- çalıştırın.
-- ============================================================================

-- Oyuncunun oynadığı maçlar (player_card.dart)
create index if not exists match_rosters_player_id_idx
  on public.match_rosters (player_id);

-- İsteğe bağlı: takım silme (deleteTeamCascade) ve takım bazlı raporlar için.
-- Takım silme nadir olduğundan şimdilik gerekli değil; tablolar büyüyünce
-- takım silmek yavaşlarsa açın.
-- create index if not exists match_rosters_team_id_idx
--   on public.match_rosters (team_id);
-- create index if not exists season_team_players_team_id_idx
--   on public.season_team_players (team_id);

-- Planner istatistiklerini tazele
analyze public.match_rosters;
analyze public.season_team_players;
