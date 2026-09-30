-- ============================================================================
-- Master Bosphorus Legends – Veteran League / ANADOLU YAKASI
-- Mevcut "2026-2027 Sezonu"na "Anadolu Yakası" grubu + 8 takım + 1. ve 2. hafta
--
-- Önkoşul: seed_bosphorus_legends_2026.sql daha önce çalıştırılmış olmalı
-- (turnuva ve sezon bu script ile oluşturulmaz, isimle bulunur).
--
--
-- Supabase SQL Editor'da bir kez çalıştırın (tekrar çalıştırılırsa grup ve
-- maçlar ikinci kez oluşur).
-- ============================================================================
do $$
declare
  -- İsterseniz maç tarihlerini buraya yazın (ör. '2026-09-26'). Boş kalırsa
  -- maçlar fikstürde ilgili haftada görünür, tarih bazlı listede görünmez.
  v_week1_date date := null;
  v_week2_date date := null;
  v_match_time text := null;          -- ör. '20:00'

  v_league_id uuid;
  v_season_id uuid;
  v_group_id  uuid;
  v_team_ids  jsonb := '{}'::jsonb;
  v_name      text;
  v_team_id   uuid;
begin
  -- 1) Mevcut turnuva + sezon
  select id into v_league_id
  from public.leagues
  where name = 'Master Bosphorus Legends'
  order by created_at desc
  limit 1;

  if v_league_id is null then
    raise exception 'Master Bosphorus Legends turnuvası bulunamadı';
  end if;

  select id into v_season_id
  from public.seasons
  where league_id = v_league_id and name = '2026-2027 Sezonu'
  limit 1;

  if v_season_id is null then
    raise exception '2026-2027 Sezonu bulunamadı';
  end if;

  -- 2) Anadolu Yakası grubu (sezon artık 2 gruplu)
  insert into public.groups (season_id, name)
  values (v_season_id, 'Anadolu Yakası')
  returning id into v_group_id;

  update public.seasons
  set number_of_groups = (select count(*) from public.groups where season_id = v_season_id)
  where id = v_season_id;

  -- 3) Takımlar (varsa mevcut kayıt kullanılır) + sezon/grup bağlantısı
  foreach v_name in array array[
    'Kanlıca Masters',
    'Boğazın Yargıçları',
    'Çeşme 1966 Masterlar',
    'Çavuşbaşı Master',
    'Paşabahçe',
    'Çağdaş Veteranlar',
    'Çotanak Masterler',
    'Site Telekom FK'
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

  -- 4) Maçlar
  insert into public.matches (
    league_id, season_id, group_id, week,
    home_team_id, away_team_id,
    home_score, away_score, status, is_completed,
    match_date, match_time
  )
  values
    -- 1. hafta
    (v_league_id, v_season_id, v_group_id, 1,
     (v_team_ids->>'Kanlıca Masters')::uuid,
     (v_team_ids->>'Site Telekom FK')::uuid,
     4, 1, 'finished', true, v_week1_date, v_match_time),

    (v_league_id, v_season_id, v_group_id, 1,
     (v_team_ids->>'Boğazın Yargıçları')::uuid,
     (v_team_ids->>'Çeşme 1966 Masterlar')::uuid,
     3, 1, 'finished', true, v_week1_date, v_match_time),

    (v_league_id, v_season_id, v_group_id, 1,
     (v_team_ids->>'Paşabahçe')::uuid,
     (v_team_ids->>'Çotanak Masterler')::uuid,
     3, 2, 'finished', true, v_week1_date, v_match_time),

    (v_league_id, v_season_id, v_group_id, 1,
     (v_team_ids->>'Çağdaş Veteranlar')::uuid,
     (v_team_ids->>'Çavuşbaşı Master')::uuid,
     2, 1, 'finished', true, v_week1_date, v_match_time),

    -- 2. hafta (gerçek skorlar)
    (v_league_id, v_season_id, v_group_id, 2,
     (v_team_ids->>'Çavuşbaşı Master')::uuid,
     (v_team_ids->>'Site Telekom FK')::uuid,
     3, 1, 'finished', true, v_week2_date, v_match_time),

    (v_league_id, v_season_id, v_group_id, 2,
     (v_team_ids->>'Çağdaş Veteranlar')::uuid,
     (v_team_ids->>'Çeşme 1966 Masterlar')::uuid,
     3, 7, 'finished', true, v_week2_date, v_match_time),

    (v_league_id, v_season_id, v_group_id, 2,
     (v_team_ids->>'Paşabahçe')::uuid,
     (v_team_ids->>'Kanlıca Masters')::uuid,
     1, 3, 'finished', true, v_week2_date, v_match_time),

    (v_league_id, v_season_id, v_group_id, 2,
     (v_team_ids->>'Boğazın Yargıçları')::uuid,
     (v_team_ids->>'Çotanak Masterler')::uuid,
     3, 0, 'finished', true, v_week2_date, v_match_time);

  raise notice 'Turnuva: %, Sezon: %, Anadolu grubu: %', v_league_id, v_season_id, v_group_id;
end $$;
