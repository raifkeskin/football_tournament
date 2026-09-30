-- ============================================================================
-- Master Bosphorus Legends – ANADOLU YAKASI / 1. hafta gerçek skorları
--
-- seed_bosphorus_legends_anadolu_2026.sql ile 1-0 olarak girilen 1. hafta
-- maçlarını gerçek skorlarla günceller. Maçlar takım isimleriyle bulunur;
-- ev sahibi/deplasman ters girilmişse skor da ters yazılır.
--
-- Tekrar çalıştırılması güvenlidir (aynı skorları yeniden yazar).
-- Herhangi bir maç bulunamazsa hiçbir değişiklik yapılmadan hata verir.
-- ============================================================================
do $$
declare
  v_season_id uuid;
  v_group_id  uuid;
  v_row       record;
  v_home_id   uuid;
  v_away_id   uuid;
  v_updated   int;
begin
  select s.id into v_season_id
  from public.seasons s
  join public.leagues l on l.id = s.league_id
  where l.name = 'Master Bosphorus Legends' and s.name = '2026-2027 Sezonu'
  order by l.created_at desc
  limit 1;

  if v_season_id is null then
    raise exception 'Master Bosphorus Legends / 2026-2027 Sezonu bulunamadı';
  end if;

  select id into v_group_id
  from public.groups
  where season_id = v_season_id and name = 'Anadolu Yakası'
  limit 1;

  if v_group_id is null then
    raise exception 'Anadolu Yakası grubu bulunamadı';
  end if;

  for v_row in
    select * from (values
      ('Boğazın Yargıçları', 'Çeşme 1966 Masterlar', 3, 1),
      ('Çağdaş Veteranlar',  'Çavuşbaşı Master',     2, 1),
      ('Paşabahçe',          'Çotanak Masterler',    3, 2),
      ('Kanlıca Masters',    'Site Telekom FK',      4, 1)
    ) as t(home_name, away_name, home_score, away_score)
  loop
    -- Takımları bu sezonun Anadolu grubundaki kayıtlar arasından bul
    select st.team_id into v_home_id
    from public.season_teams st
    join public.teams tm on tm.id = st.team_id
    where st.season_id = v_season_id and st.group_id = v_group_id
      and tm.name = v_row.home_name
    limit 1;

    select st.team_id into v_away_id
    from public.season_teams st
    join public.teams tm on tm.id = st.team_id
    where st.season_id = v_season_id and st.group_id = v_group_id
      and tm.name = v_row.away_name
    limit 1;

    if v_home_id is null or v_away_id is null then
      raise exception 'Takım bulunamadı: % / %', v_row.home_name, v_row.away_name;
    end if;

    update public.matches m
    set home_score = case when m.home_team_id = v_home_id
                          then v_row.home_score else v_row.away_score end,
        away_score = case when m.home_team_id = v_home_id
                          then v_row.away_score else v_row.home_score end,
        status = 'finished',
        is_completed = true
    where m.season_id = v_season_id
      and m.group_id = v_group_id
      and m.week = 1
      and ((m.home_team_id = v_home_id and m.away_team_id = v_away_id)
        or (m.home_team_id = v_away_id and m.away_team_id = v_home_id));

    get diagnostics v_updated = row_count;
    if v_updated <> 1 then
      raise exception '1. hafta maçı için % kayıt bulundu (1 bekleniyordu): % - %',
        v_updated, v_row.home_name, v_row.away_name;
    end if;

    raise notice '% % - % %', v_row.home_name, v_row.home_score,
      v_row.away_score, v_row.away_name;
  end loop;
end $$;
