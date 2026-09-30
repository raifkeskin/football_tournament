-- ============================================================================
-- Master Bosphorus Legends – fikstür
--
-- AVRUPA YAKASI / 2. hafta
--   04.10.2026 Pazar – Seyrantepe Stadı
--     18:30  Kardeşler Matbaa Masterler  - İstanbul Sivas Masterler
--     19:40  Kuzeyin Aslanları Masterler - Gaziosmanpaşa Autur Masterler
--     20:50  Albatros Masterler          - Dinamo Tonya Masterler
--   07.10.2026 Çarşamba – Eyüp Bahariye Stadı
--     22:00  Boğaziçi Masterler          - Sarıyer Masterler
--
-- ANADOLU YAKASI / 3. hafta
--   03.10.2026 Cumartesi – Paşabahçe Stadı
--     19:30  Paşabahçe                   - Site Telekom FK
--     21:00  Çeşme 1966 Masterlar        - Çavuşbaşı Master
--   04.10.2026 Pazar – Paşabahçe Stadı
--     19:30  Çotanak Masterler           - Çağdaş Veteranlar
--     21:00  Kanlıca Masters             - Boğazın Yargıçları
--
-- Her maçın grubu, ev sahibi takımın bu sezonda bağlı olduğu gruptan bulunur;
-- deplasman takımı aynı grupta değilse hata verir.
-- Saha pitches tablosunda yoksa oluşturulur.
-- Tekrar çalıştırılması güvenlidir: maç o haftada zaten varsa tarih/saat/saha
-- güncellenir, yoksa eklenir. Herhangi bir takım bulunamazsa hiçbir değişiklik
-- yapılmadan hata verir.
-- ============================================================================
do $$
declare
  v_league_id uuid;
  v_season_id uuid;
  v_group_id  uuid;
  v_pitch_id  uuid;
  v_row       record;
  v_home_id   uuid;
  v_away_id   uuid;
  v_match_id  uuid;
begin
  select l.id, s.id into v_league_id, v_season_id
  from public.seasons s
  join public.leagues l on l.id = s.league_id
  where l.name = 'Master Bosphorus Legends' and s.name = '2026-2027 Sezonu'
  order by l.created_at desc
  limit 1;

  if v_season_id is null then
    raise exception 'Master Bosphorus Legends / 2026-2027 Sezonu bulunamadı';
  end if;

  for v_row in
    select * from (values
      -- Avrupa Yakası / 2. hafta
      (2, 'Kardeşler Matbaa Masterler',  'İstanbul Sivas Masterler',      date '2026-10-04', '18:30', 'Seyrantepe Stadı'),
      (2, 'Kuzeyin Aslanları Masterler', 'Gaziosmanpaşa Autur Masterler', date '2026-10-04', '19:40', 'Seyrantepe Stadı'),
      (2, 'Albatros Masterler',          'Dinamo Tonya Masterler',        date '2026-10-04', '20:50', 'Seyrantepe Stadı'),
      (2, 'Boğaziçi Masterler',          'Sarıyer Masterler',             date '2026-10-07', '22:00', 'Eyüp Bahariye Stadı'),
      -- Anadolu Yakası / 3. hafta
      (3, 'Paşabahçe',                   'Site Telekom FK',               date '2026-10-03', '19:30', 'Paşabahçe Stadı'),
      (3, 'Çeşme 1966 Masterlar',        'Çavuşbaşı Master',              date '2026-10-03', '21:00', 'Paşabahçe Stadı'),
      (3, 'Çotanak Masterler',           'Çağdaş Veteranlar',             date '2026-10-04', '19:30', 'Paşabahçe Stadı'),
      (3, 'Kanlıca Masters',             'Boğazın Yargıçları',            date '2026-10-04', '21:00', 'Paşabahçe Stadı')
    ) as t(week, home_name, away_name, match_date, match_time, pitch_name)
  loop
    -- Ev sahibi takım ve grubu
    v_home_id := null;
    v_group_id := null;
    select st.team_id, st.group_id into v_home_id, v_group_id
    from public.season_teams st
    join public.teams tm on tm.id = st.team_id
    where st.season_id = v_season_id and tm.name = v_row.home_name
    limit 1;

    -- Deplasman takımı (aynı grupta olmalı)
    v_away_id := null;
    select st.team_id into v_away_id
    from public.season_teams st
    join public.teams tm on tm.id = st.team_id
    where st.season_id = v_season_id and st.group_id = v_group_id
      and tm.name = v_row.away_name
    limit 1;

    if v_home_id is null or v_away_id is null then
      raise exception 'Takım bulunamadı: % / %', v_row.home_name, v_row.away_name;
    end if;

    -- Saha (yoksa oluştur)
    v_pitch_id := null;
    select id into v_pitch_id from public.pitches
    where lower(name) = lower(v_row.pitch_name)
    limit 1;

    if v_pitch_id is null then
      insert into public.pitches (name, city, country)
      values (v_row.pitch_name, 'İstanbul', 'Türkiye')
      returning id into v_pitch_id;
    end if;

    -- Maç varsa güncelle, yoksa ekle
    v_match_id := null;
    select m.id into v_match_id
    from public.matches m
    where m.season_id = v_season_id
      and m.group_id = v_group_id
      and m.week = v_row.week
      and ((m.home_team_id = v_home_id and m.away_team_id = v_away_id)
        or (m.home_team_id = v_away_id and m.away_team_id = v_home_id))
    limit 1;

    if v_match_id is not null then
      update public.matches
      set match_date = v_row.match_date,
          match_time = v_row.match_time,
          pitch_id   = v_pitch_id
      where id = v_match_id;
    else
      insert into public.matches (
        league_id, season_id, group_id, week,
        home_team_id, away_team_id,
        home_score, away_score, status, is_completed,
        match_date, match_time, pitch_id
      )
      values (
        v_league_id, v_season_id, v_group_id, v_row.week,
        v_home_id, v_away_id,
        0, 0, 'notStarted', false,
        v_row.match_date, v_row.match_time, v_pitch_id
      );
    end if;

    raise notice '%. hafta % % % - % (%)', v_row.week, v_row.match_date,
      v_row.match_time, v_row.home_name, v_row.away_name, v_row.pitch_name;
  end loop;
end $$;
