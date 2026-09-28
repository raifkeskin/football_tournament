-- ============================================================================
-- Master Bosphorus Legends – Veteran League
-- Turnuva + "2026-2027 Sezonu" + tek grup + 8 takım + 1. hafta fikstürü
--
-- Supabase SQL Editor'da tek seferde çalıştırın. Aynı isimde bir takım zaten
-- varsa yenisi oluşturulmaz, mevcut takım kullanılır. Script tekrar
-- çalıştırılırsa turnuva/sezon ikinci kez oluşur; bu yüzden bir kez çalıştırın.
-- ============================================================================
do $$
declare
  -- İsterseniz 1. hafta maç tarih/saatini buraya yazın (ör. '2026-09-26').
  -- Boş (null) kalırsa maçlar fikstürde 1. haftada görünür, ana sayfadaki
  -- tarih bazlı listede görünmez.
  v_week1_date date := null;
  v_week1_time text := null;          -- ör. '20:00'

  v_league_id uuid;
  v_season_id uuid;
  v_group_id  uuid;
  v_team_ids  jsonb := '{}'::jsonb;
  v_name      text;
  v_team_id   uuid;
begin
  -- 1) Turnuva
  insert into public.leagues (name, is_private, is_active)
  values ('Master Bosphorus Legends', false, true)
  returning id into v_league_id;

  -- 2) Sezon
  insert into public.seasons (
    league_id, name, subtitle, start_date, end_date,
    starting_player_count, sub_player_count,
    country, city, is_active, is_default,
    teams_per_group, number_of_groups,
    match_period_duration, number_of_player_changes
  )
  values (
    v_league_id, '2026-2027 Sezonu', 'Veteran League', '2026-09-01', '2027-06-30',
    11, 7,
    'Türkiye', 'İstanbul', true, true,
    8, 1,
    30, 7
  )
  returning id into v_season_id;

  -- 3) Grup (tek grup)
  insert into public.groups (season_id, name)
  values (v_season_id, 'Bosphorus Legends')
  returning id into v_group_id;

  -- 4) Takımlar (varsa mevcut kayıt kullanılır) + sezon/grup bağlantısı
  foreach v_name in array array[
    'Dinamo Tonya Masterler',
    'Gaziosmanpaşa Autur Masterler',
    'Albatros Masterler',
    'Boğaziçi Masterler',
    'Kardeşler Matbaa Masterler',
    'Kuzeyin Aslanları Masterler',
    'Sarıyer Masterler',
    'İstanbul Sivas Masterler'
  ]
  loop
    select id into v_team_id from public.teams where name = v_name limit 1;
    if v_team_id is null then
      insert into public.teams (name) values (v_name) returning id into v_team_id;
    end if;

    insert into public.season_teams (season_id, team_id, group_id)
    values (v_season_id, v_team_id, v_group_id);

    v_team_ids := v_team_ids || jsonb_build_object(v_name, v_team_id);
    v_team_id := null;
  end loop;

  -- 5) 1. hafta maçları (3 maç oynandı, 1 maç oynanmadı)
  insert into public.matches (
    league_id, season_id, group_id, week,
    home_team_id, away_team_id,
    home_score, away_score, status, is_completed,
    match_date, match_time
  )
  values
    (v_league_id, v_season_id, v_group_id, 1,
     (v_team_ids->>'Gaziosmanpaşa Autur Masterler')::uuid,
     (v_team_ids->>'Sarıyer Masterler')::uuid,
     6, 1, 'finished', true, v_week1_date, v_week1_time),

    (v_league_id, v_season_id, v_group_id, 1,
     (v_team_ids->>'Dinamo Tonya Masterler')::uuid,
     (v_team_ids->>'İstanbul Sivas Masterler')::uuid,
     6, 0, 'finished', true, v_week1_date, v_week1_time),

    (v_league_id, v_season_id, v_group_id, 1,
     (v_team_ids->>'Albatros Masterler')::uuid,
     (v_team_ids->>'Kuzeyin Aslanları Masterler')::uuid,
     5, 1, 'finished', true, v_week1_date, v_week1_time),

    (v_league_id, v_season_id, v_group_id, 1,
     (v_team_ids->>'Kardeşler Matbaa Masterler')::uuid,
     (v_team_ids->>'Boğaziçi Masterler')::uuid,
     0, 0, 'notStarted', false, v_week1_date, v_week1_time);

  raise notice 'Turnuva: %, Sezon: %, Grup: %', v_league_id, v_season_id, v_group_id;
end $$;
