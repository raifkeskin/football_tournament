-- Demo turnuvaları ve Demo Başkan hesabını (yeniden) kurar.
--
--   select public.demo_reset();
--
-- * Demo Masterlar Ligi: 2 bölge (Avrupa / Anadolu), 8+8 takım, son 4 hafta
--   oynanmış; Demo Okul Kupası: tek grup, 6 takım, son 2 hafta oynanmış.
-- * Oynanmış maçlarda kadro (esame + diziliş), gol, asist, sarı/kırmızı kart,
--   oyuncu değişikliği, maçın adamı ve yayın linki bulunur; kartlardan doğan
--   cezaların bir kısmı onaylı, biri onay bekliyor.
-- * Tarihler çalıştırıldığı güne göre kurulur (son oynanan hafta geçen
--   cumartesi), böylece gece sıfırlanırsa demo hep güncel görünür.
-- * Turnuvalar leagues.is_demo = true: yalnızca sahipleri ve admin görür.
-- * Haber ve maç bildirimi tetikleyicileri kurulum sırasında kapalıdır.
-- * Demo hesabı: 500 000 00 00 / demo2026 (şifre her kurulumda sıfırlanır).
--
-- Fonksiyonlar yalnızca veritabanı sahibi tarafından çalıştırılabilir.

create or replace function public._demo_build_season(
  p_league uuid,
  p_season_name text,
  p_regions text[],          -- null: bölgesiz
  p_groups text[],
  p_teams text[],            -- grup sırasıyla, grup başına p_per_group takım
  p_per_group int,
  p_starting int,            -- 11 ya da 7
  p_period int,              -- devre süresi (dakika)
  p_changes int,
  p_played_weeks int,
  p_first_date date,         -- 1. haftanın tarihi
  p_times text[],            -- haftalık maç saatleri (grup içi sırayla)
  p_pitches uuid[],          -- grup başına saha
  p_birth_from int,
  p_birth_to int,
  p_first_names text[],
  p_formation text,
  p_stream_url text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  c_last_names constant text[] := array[
    'Yılmaz','Kaya','Demir','Şahin','Çelik','Yıldız','Yıldırım','Öztürk',
    'Aydın','Özdemir','Arslan','Doğan','Kılıç','Aslan','Çetin','Kara','Koç',
    'Kurt','Özkan','Şimşek','Polat','Korkmaz','Karaca','Erdem','Güneş',
    'Aksoy','Tekin','Bulut','Uçar','Ateş','Bozkurt','Toprak','Coşkun',
    'Duman','Tuna','Sarı','Akın','Avcı','Ekinci','Kalkan','Turan','Önal'];
  c_colors constant text[] := array[
    '#B91C1C','#1D4ED8','#047857','#7C3AED','#EA580C','#0F766E','#BE185D',
    '#1E3A8A','#CA8A04','#334155','#15803D','#9F1239','#0369A1','#4D7C0F',
    '#C2410C','#6D28D9'];
  v_pos text[];
  v_jersey int[];
  v_squad int;
  v_season uuid;
  v_region uuid;
  v_group uuid;
  v_groups uuid[] := '{}';
  v_team uuid;
  v_player uuid;
  v_fn text;
  v_ln text;
  v_n int := array_length(p_groups, 1);
  v_last_week_date date;
  g int; i int; k int; r int; w int;
  v_arr uuid[];
  v_rot uuid[];
  v_home uuid; v_away uuid;
  v_match uuid;
  v_date date;
  v_status public.match_status;
  v_hs int; v_as int;
  v_side int;
  v_team_id uuid;
  v_opp uuid;
  v_starters uuid[];
  v_bench uuid[];
  v_weighted uuid[];
  v_outfield uuid[];
  v_goals int;
  v_scorer uuid;
  v_assist uuid;
  v_motm uuid;
  v_motm_team uuid;
  v_carded uuid[];
  v_out uuid;
  v_in uuid;
  v_min int;
  v_full int := p_period * 2;
  c_goal_dist constant int[] := array[0,0,1,1,1,2,2,2,3,3,4,5];
  c_card_dist constant int[] := array[0,0,1,1,1,2,2,3];
begin
  if p_starting = 7 then
    v_pos := array['Kaleci','Defans','Defans','Orta Saha','Orta Saha','Kanat',
                   'Forvet','Defans','Orta Saha','Forvet'];
    v_jersey := array[1,2,4,6,8,7,9,12,14,17];
  else
    v_pos := array['Kaleci','Defans','Defans','Defans','Defans','Orta Saha',
                   'Orta Saha','Kanat','On Numara','Forvet','Forvet',
                   'Defans','Orta Saha','Forvet'];
    v_jersey := array[1,2,3,4,5,6,8,7,10,9,11,13,14,19];
  end if;
  v_squad := array_length(v_pos, 1);

  insert into public.seasons (
    league_id, name, start_date, end_date, city, country, is_active,
    is_default, number_of_groups, teams_per_group, match_period_duration,
    starting_player_count, sub_player_count, number_of_player_changes,
    is_double_round)
  values (
    p_league, p_season_name, p_first_date - 7,
    p_first_date + 7 * (p_per_group + 2), 'İstanbul', 'Türkiye', true,
    false, v_n, p_per_group, p_period, p_starting, v_squad - p_starting,
    p_changes, false)
  returning id into v_season;

  for g in 1..v_n loop
    v_region := null;
    if p_regions is not null then
      insert into public.season_regions (season_id, name, city, sort_order)
      values (v_season, p_regions[g], 'İstanbul', g)
      returning id into v_region;
    end if;
    insert into public.groups (season_id, name, region_id)
    values (v_season, p_groups[g], v_region)
    returning id into v_group;
    v_groups := v_groups || v_group;

    -- Takımlar ve kadroları.
    v_arr := '{}';
    for i in 1..p_per_group loop
      k := (g - 1) * p_per_group + i;
      insert into public.teams (name, first_color, second_color)
      values (p_teams[k], c_colors[1 + (k - 1) % array_length(c_colors, 1)],
              '#FFFFFF')
      returning id into v_team;
      insert into public.season_teams (team_id, season_id, group_id)
      values (v_team, v_season, v_group);
      v_arr := v_arr || v_team;

      for r in 1..v_squad loop
        -- Sezon içinde aynı ad soyad iki kez kullanılmaz.
        loop
          v_fn := p_first_names[1 + floor(random() * array_length(p_first_names, 1))::int];
          v_ln := c_last_names[1 + floor(random() * array_length(c_last_names, 1))::int];
          exit when not exists (
            select 1 from public.season_team_players stp
            join public.players p on p.id = stp.player_id
            where stp.season_id = v_season and p.name = v_fn and p.surname = v_ln);
        end loop;
        insert into public.players (
          name, surname, birth_date, main_position, preferred_foot)
        values (
          v_fn,
          v_ln,
          make_date(p_birth_from + floor(random() * (p_birth_to - p_birth_from + 1))::int,
                    1 + floor(random() * 12)::int, 1 + floor(random() * 28)::int),
          v_pos[r],
          case when random() < 0.75 then 'Sağ' else 'Sol' end)
        returning id into v_player;
        insert into public.season_team_players (
          player_id, team_id, season_id, jersey_number, is_active)
        values (v_player, v_team, v_season, v_jersey[r], true);
      end loop;
    end loop;

    -- Tek devreli fikstür (çember yöntemi); haftalar cumartesi.
    v_rot := v_arr;
    for w in 1..(p_per_group - 1) loop
      v_date := p_first_date + 7 * (w - 1);
      for i in 1..(p_per_group / 2) loop
        if (w + i) % 2 = 0 then
          v_home := v_rot[i]; v_away := v_rot[p_per_group + 1 - i];
        else
          v_home := v_rot[p_per_group + 1 - i]; v_away := v_rot[i];
        end if;
        v_status := case when w <= p_played_weeks
                         then 'finished'::public.match_status
                         else 'notStarted'::public.match_status end;
        v_hs := null; v_as := null;
        if v_status = 'finished' then
          v_hs := c_goal_dist[1 + floor(random() * 12)::int];
          v_as := c_goal_dist[1 + floor(random() * 12)::int];
        end if;
        insert into public.matches (
          season_id, league_id, group_id, home_team_id, away_team_id,
          pitch_id, week, match_date, match_time, status, is_completed,
          home_score, away_score, home_formation, away_formation)
        values (
          v_season, p_league, v_group, v_home, v_away, p_pitches[g], w,
          v_date, p_times[1 + (i - 1) % array_length(p_times, 1)], v_status,
          v_status = 'finished', v_hs, v_as,
          case when v_status = 'finished' then p_formation end,
          case when v_status = 'finished' then p_formation end)
        returning id into v_match;

        if v_status = 'finished' then
          insert into public.match_media (match_id, media_type, url)
          values (v_match, 'Maç Yayın Linki', p_stream_url);

          v_motm := null; v_motm_team := null;
          for v_side in 1..2 loop
            v_team_id := case v_side when 1 then v_home else v_away end;
            v_opp := case v_side when 1 then v_away else v_home end;
            v_goals := case v_side when 1 then v_hs else v_as end;

            select array_agg(player_id order by id) filter (where rn <= p_starting),
                   array_agg(player_id order by id) filter (where rn > p_starting)
              into v_starters, v_bench
            from (
              select stp.id, stp.player_id,
                     row_number() over (order by stp.id) as rn
              from public.season_team_players stp
              where stp.season_id = v_season and stp.team_id = v_team_id
            ) s;

            -- Esame: ilk 11 (7) dizilişe göre sırayla, yedekler sonra.
            insert into public.match_rosters (
              match_id, team_id, player_id, is_starting, jersey_number,
              pos_x, is_home, is_captain, league_id)
            select v_match, v_team_id, stp.player_id, s.rn <= p_starting,
                   stp.jersey_number,
                   case when s.rn <= p_starting then s.rn - 1 end,
                   (v_side = 1)::text, s.rn = p_starting - 2, p_league
            from (
              select stp2.id, row_number() over (order by stp2.id) as rn
              from public.season_team_players stp2
              where stp2.season_id = v_season and stp2.team_id = v_team_id
            ) s
            join public.season_team_players stp on stp.id = s.id;

            -- Gol atma olasılığı forvetlerde yüksek; kaleci gol atmaz.
            v_weighted := '{}';
            v_outfield := v_starters[2:p_starting];
            for k in 2..p_starting loop
              v_weighted := v_weighted || array_fill(
                v_starters[k],
                array[case v_pos[k]
                        when 'Forvet' then 6 when 'On Numara' then 4
                        when 'Kanat' then 3 when 'Orta Saha' then 2
                        else 1 end]);
            end loop;

            for k in 1..v_goals loop
              v_scorer := v_weighted[1 + floor(random() * array_length(v_weighted, 1))::int];
              v_assist := null;
              if random() < 0.65 then
                v_assist := v_weighted[1 + floor(random() * array_length(v_weighted, 1))::int];
                if v_assist = v_scorer then v_assist := null; end if;
              end if;
              insert into public.match_events (
                match_id, team_id, player_id, assist_player_id, event_type,
                minute, is_own_goal)
              values (v_match, v_team_id, v_scorer, v_assist, 'goal',
                      1 + floor(random() * v_full)::int, false);
              if v_motm is null and (v_goals > case v_side when 1 then v_as else v_hs end
                                     or (v_side = 2 and v_motm_team is null)) then
                v_motm := v_scorer; v_motm_team := v_team_id;
              end if;
            end loop;

            -- Sarı kartlar; bazen ikinci sarı, nadiren direkt kırmızı.
            v_carded := '{}';
            for k in 1..c_card_dist[1 + floor(random() * 8)::int] loop
              v_scorer := v_outfield[1 + floor(random() * (p_starting - 1))::int];
              if v_scorer = any(v_carded) then continue; end if;
              v_carded := v_carded || v_scorer;
              v_min := 5 + floor(random() * (v_full - 15))::int;
              insert into public.match_events (match_id, team_id, player_id, event_type, minute)
              values (v_match, v_team_id, v_scorer, 'yellow_card', v_min);
              if random() < 0.05 then
                insert into public.match_events (match_id, team_id, player_id, event_type, minute)
                values (v_match, v_team_id, v_scorer, 'yellow_card',
                        least(v_full, v_min + 5 + floor(random() * 10)::int));
              end if;
            end loop;
            -- Son iki haftanın ilk maçında birer kırmızı: biri onaylı ve
            -- süren, biri onay bekleyen ceza olarak görünsün.
            if random() < 0.04
               or (i = 1 and w = p_played_weeks and v_side = 2)
               or (i = 1 and w = p_played_weeks - 1 and v_side = 1) then
              -- Kart görmemiş bir oyuncu (savunmadan başlayarak).
              select x into v_scorer from unnest(v_outfield) x
              where not (x = any(v_carded)) limit 1;
              if v_scorer is not null then
                insert into public.match_events (match_id, team_id, player_id, event_type, minute)
                values (v_match, v_team_id, v_scorer, 'red_card',
                        10 + floor(random() * (v_full - 10))::int);
              end if;
            end if;

            -- Oyuncu değişiklikleri (çıkan: player_id, giren: sub_in_player_id).
            for k in 1..least(2, coalesce(array_length(v_bench, 1), 0)) loop
              v_out := v_outfield[p_starting - 1 - (k - 1) * 2];
              v_in := v_bench[k];
              insert into public.match_events (
                match_id, team_id, player_id, sub_in_player_id, event_type, minute)
              values (v_match, v_team_id, v_out, v_in, 'substitution',
                      p_period + floor(random() * (p_period - 5))::int);
            end loop;
          end loop;

          -- Maçın adamı: kazanan takımın golcüsü; yoksa ev sahibinin 10'u.
          if v_motm is null then
            select stp.player_id into v_motm
            from public.season_team_players stp
            where stp.season_id = v_season and stp.team_id = v_home
            order by stp.id offset p_starting - 3 limit 1;
            v_motm_team := v_home;
          end if;
          insert into public.match_events (match_id, team_id, player_id, event_type, minute)
          values (v_match, v_motm_team, v_motm, 'man_of_the_match', 999);
        end if;
      end loop;
      -- Çember: ilk takım sabit, diğerleri bir adım döner.
      v_rot := array[v_rot[1]] || v_rot[p_per_group:p_per_group]
               || v_rot[2:p_per_group - 1];
    end loop;
  end loop;

  -- Kart cezaları (tetikleyici "onay bekliyor" olarak açar): son oynanan
  -- haftanınkiler onay bekler; öncekiler onaylı ve oynanan maçlar kadar
  -- çekilmiş (bir önceki haftanın kırmızısı 1 maç daha sürer).
  v_last_week_date := p_first_date + 7 * (p_played_weeks - 1);
  update public.player_penalties pp
     set status = 'approved',
         remaining_matches = greatest(
           pp.match_count - (v_last_week_date - m.match_date) / 7, 0),
         is_active = pp.match_count - (v_last_week_date - m.match_date) / 7 > 0,
         reviewed_at = now()
    from public.matches m
   where pp.match_id = m.id and pp.season_id = v_season
     and m.match_date < v_last_week_date;

  return v_season;
end;
$$;

create or replace function public.demo_reset()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  c_user constant uuid := 'd0000000-0000-4000-8000-0000000000aa';
  c_phone constant text := '5000000000';
  c_password constant text := 'demo2026';
  c_l1 constant uuid := 'd0000000-0000-4000-8000-000000000001';
  c_l2 constant uuid := 'd0000000-0000-4000-8000-000000000002';
  c_stream constant text := 'https://www.youtube.com/live/U_cmG_3xPxg';
  c_names_adult constant text[] := array[
    'Ahmet','Mehmet','Mustafa','Ali','Hüseyin','Hasan','İbrahim','Murat',
    'Ömer','Yusuf','Emre','Burak','Serkan','Volkan','Kemal','Erkan','Tolga',
    'Cem','Barış','Onur','Selim','Okan','Levent','Hakan','Tuncay','Sinan',
    'Gökhan','Ercan','Taner','Engin','Caner','Uğur','Fatih','Kaan','Orhan',
    'Bülent','Cengiz','Halil','Zafer','İlker'];
  c_names_kid constant text[] := array[
    'Efe','Arda','Kerem','Eymen','Yiğit','Mert','Berat','Ege','Doruk','Alp',
    'Çınar','Aras','Poyraz','Ömer','Emir','Miraç','Kuzey','Atlas','Deniz',
    'Batuhan','Yusuf','Kaan','Eren','Tuna'];
  v_teams uuid[];
  v_players uuid[];
  v_last_sat date;
  v_s1 uuid;
  v_s2 uuid;
  v_r1 uuid;
  v_r2 uuid;
  v_txt text;
  v_txt2 text;
begin
  perform setseed(0.2026);

  -- 1) Eski demo verisini sil (yalnızca demo sezonlarında yer alan takım ve
  --    oyuncular; demo hesabının sonradan eklediği kayıtlar da gider).
  select coalesce(array_agg(distinct st.team_id), '{}') into v_teams
  from public.season_teams st
  join public.seasons s on s.id = st.season_id
  where s.league_id in (c_l1, c_l2)
    and not exists (
      select 1 from public.season_teams x
      join public.seasons y on y.id = x.season_id
      where x.team_id = st.team_id and y.league_id not in (c_l1, c_l2));
  select coalesce(array_agg(distinct stp.player_id), '{}') into v_players
  from public.season_team_players stp
  join public.seasons s on s.id = stp.season_id
  where s.league_id in (c_l1, c_l2)
    and not exists (
      select 1 from public.season_team_players x
      join public.seasons y on y.id = x.season_id
      where x.player_id = stp.player_id and y.league_id not in (c_l1, c_l2));

  delete from public.matches where league_id in (c_l1, c_l2)
    or season_id in (select id from public.seasons where league_id in (c_l1, c_l2));
  delete from public.seasons where league_id in (c_l1, c_l2);
  delete from public.teams where id = any(v_teams);
  delete from public.players where id = any(v_players) and auth_uid is null;
  delete from public.leagues where id in (c_l1, c_l2);

  -- 2) Demo Başkan hesabı (telefon 500 000 00 00).
  if not exists (select 1 from auth.users where id = c_user) then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change)
    values (
      '00000000-0000-0000-0000-000000000000', c_user, 'authenticated',
      'authenticated', c_phone || '@masterclass.com',
      extensions.crypt(c_password, extensions.gen_salt('bf')), now(),
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      '{"email_verified": true, "must_change_password": false, "name": "Demo Başkan"}'::jsonb,
      now(), now(), '', '', '', '');
    insert into auth.identities (
      provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at)
    values (
      c_user::text, c_user,
      jsonb_build_object('sub', c_user::text,
                         'email', c_phone || '@masterclass.com',
                         'email_verified', false, 'phone_verified', false),
      'email', now(), now(), now());
  else
    update auth.users
       set encrypted_password = extensions.crypt(c_password, extensions.gen_salt('bf')),
           raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
             || '{"must_change_password": false, "name": "Demo Başkan"}'::jsonb,
           updated_at = now()
     where id = c_user;
  end if;
  insert into public.app_users (phone, name, auth_uid, role)
  values (c_phone, 'Demo Başkan', c_user::text, 'player')
  on conflict (phone) do update
    set auth_uid = excluded.auth_uid, name = excluded.name;

  -- 3) Turnuvalar (bildirim tetikleyicileri kurulum boyunca kapalı).
  alter table public.matches disable trigger matches_push_notify;
  alter table public.news disable trigger news_push_notify;

  insert into public.leagues (
    id, name, short_name, is_private, is_demo, access_code, is_active,
    theme_primary, theme_secondary, roster_open_hours)
  values
    (c_l1, 'Demo Masterlar Ligi', 'Demo Masterlar', true, true, '730415',
     true, '#0F3D2E', '#E0A526', 1),
    (c_l2, 'Demo Okul Kupası', 'Demo Okul Kupası', true, true, '730416',
     true, '#1D4ED8', '#F59E0B', 1);
  insert into public.league_owners (league_id, user_id)
  values (c_l1, c_user), (c_l2, c_user);

  -- Son oynanan hafta: bugünden önceki son cumartesi.
  v_last_sat := current_date
    - case when extract(isodow from current_date)::int = 6 then 7
           else (extract(isodow from current_date)::int + 1) % 7 end;

  v_s1 := public._demo_build_season(
    c_l1, '2026-2027 Sezonu',
    array['Avrupa Yakası', 'Anadolu Yakası'],
    array['Avrupa Grubu', 'Anadolu Grubu'],
    array['Kuzey Yıldızları', 'Galata Veteranlar', 'Bakırköy Dostluk',
          'Florya Kartalları', 'Şişli Efsaneler', 'Eyüp Sultanlar',
          'Beylikdüzü Masterlar', 'Haliç Spor',
          'Moda Masterlar', 'Üsküdar Dostlar', 'Ataşehir Yıldızları',
          'Maltepe Sahil', 'Kartal Veteranlar', 'Pendik Denizciler',
          'Çekmeköy Kurtları', 'Beykoz Efsaneleri'],
    8, 11, 30, 5, 4, v_last_sat - 21,
    array['19:00', '20:00', '21:00', '22:00'],
    array['415c9143-c7d0-4539-a276-e413ecf25c23'::uuid,
          'c9dd6c7d-29fe-49b9-813c-d91524e7666d'::uuid],
    1976, 1988, c_names_adult, '4-4-2', c_stream);

  v_s2 := public._demo_build_season(
    c_l2, '2026-2027 Sezonu', null,
    array['A Grubu'],
    array['Yıldız Koleji', 'Bilim Ortaokulu', 'Deniz Anadolu Lisesi',
          'Çınar Koleji', 'Ufuk Ortaokulu', 'Gökkuşağı Koleji'],
    6, 7, 20, 5, 2, v_last_sat - 7,
    array['10:00', '11:00', '12:00'],
    array['5c305a3a-574a-410b-a555-2642e187044f'::uuid],
    2011, 2013, c_names_kid, '2-3-1', c_stream);

  -- 4) Haberler (sonuçlardan üretilir).
  select id into v_r1 from public.season_regions where season_id = v_s1 and sort_order = 1;
  select id into v_r2 from public.season_regions where season_id = v_s1 and sort_order = 2;

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  join public.groups g on g.id = m.group_id
  where m.season_id = v_s1 and m.week = 4 and g.region_id = v_r1;
  insert into public.news (league_id, region_id, content, is_published, created_at)
  values (c_l1, v_r1,
    'AVRUPA GRUBUNDA 4. HAFTA TAMAMLANDI' || E'\n\n' || v_txt || E'\n\n' ||
    'Avrupa Grubu''nda dördüncü hafta geride kaldı. Puan durumu ve gol krallığı '
    || 'uygulamada güncellendi. Gelecek hafta görüşmek üzere!',
    true, (v_last_sat + 1)::timestamp + interval '10 hours');

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  join public.groups g on g.id = m.group_id
  where m.season_id = v_s1 and m.week = 4 and g.region_id = v_r2;
  insert into public.news (league_id, region_id, content, is_published, created_at)
  values (c_l1, v_r2,
    'ANADOLU GRUBUNDA 4. HAFTA SONUÇLARI' || E'\n\n' || v_txt || E'\n\n' ||
    'Anadolu Grubu''nda heyecan sürüyor. Maç özetleri ve kadrolar için maç '
    || 'detaylarına göz atabilirsiniz.',
    true, (v_last_sat + 1)::timestamp + interval '11 hours');

  -- Zirvedeki golcü(ler); beraberlikte hepsi yazılır.
  with c as (
    select p.name || ' ' || p.surname || ' (' || t.name || ')' as who,
           count(*) as n
    from public.match_events e
    join public.players p on p.id = e.player_id
    join public.teams t on t.id = e.team_id
    where e.season_id = v_s1 and e.event_type = 'goal'
    group by p.id, p.name, p.surname, t.name
  ), top as (
    select * from c where n = (select max(n) from c)
  )
  select case when count(*) = 1
           then 'zirvede ' || max(who) || ' ' || max(n) || ' golle tek başına'
           else max(n) || ' golle ' || regexp_replace(
                  string_agg(who, ', ' order by who), ', ([^,]*)$', ' ve \1')
                || ' zirveyi paylaşıyor'
         end
    into v_txt
  from top;
  select h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name
    into v_txt2
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  where m.season_id = v_s1 and m.status = 'finished'
  order by m.home_score + m.away_score desc, m.match_date desc limit 1;
  insert into public.news (league_id, content, is_published, created_at)
  values (c_l1,
    'GOL KRALLIĞINDA ZİRVE' || E'\n\n' || 'Dört haftanın ardından gol '
    || 'krallığında ' || v_txt || '. Sezonun en gollü maçı ise '
    || v_txt2 || ' karşılaşması oldu.',
    true, (v_last_sat + 2)::timestamp + interval '9 hours');

  insert into public.news (league_id, content, is_published, created_at)
  values (c_l1,
    '5. HAFTA PROGRAMI AÇIKLANDI' || E'\n\n' || 'Beşinci hafta maçları '
    || 'cumartesi günü oynanacak. Takım sorumluları esamelerini maç '
    || 'saatinden 1 saat önce uygulamadan girebilir. Cezalı oyuncular esamede '
    || 'işaretli görünür.',
    true, (v_last_sat + 2)::timestamp + interval '12 hours');

  insert into public.news (league_id, content, is_published, created_at)
  values (c_l1,
    'FAIR PLAY ÇAĞRISI' || E'\n\n' || 'Ligimizde dostluk ve centilmenlik '
    || 'her şeyden önce gelir. Hakem kararlarına saygı gösteren, rakibine '
    || 'yardım eden tüm oyuncularımıza teşekkür ederiz.',
    true, (v_last_sat - 3)::timestamp + interval '15 hours');

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  where m.season_id = v_s2 and m.week = 2;
  insert into public.news (league_id, content, is_published, created_at)
  values (c_l2,
    'OKUL KUPASI''NDA 2. HAFTA' || E'\n\n' || v_txt || E'\n\n' ||
    'Öğrencilerimizi ve onları destekleyen ailelere teşekkür ederiz.',
    true, (v_last_sat + 1)::timestamp + interval '13 hours');
  insert into public.news (league_id, content, is_published, created_at)
  values (c_l2,
    'OKUL KUPASI BAŞLADI' || E'\n\n' || 'Altı okulun katıldığı turnuvamız '
    || 'başladı. Maç programı, kadrolar ve sonuçlar uygulamada.',
    true, (v_last_sat - 8)::timestamp + interval '10 hours');

  alter table public.matches enable trigger matches_push_notify;
  alter table public.news enable trigger news_push_notify;

  return jsonb_build_object(
    'leagues', array[c_l1, c_l2],
    'login', c_phone, 'password', c_password,
    'matches', (select count(*) from public.matches where league_id in (c_l1, c_l2)),
    'events', (select count(*) from public.match_events e
               join public.matches m on m.id = e.match_id
               where m.league_id in (c_l1, c_l2)),
    'penalties', (select count(*) from public.player_penalties pp
                  where pp.season_id in (v_s1, v_s2)));
end;
$$;

revoke all on function public._demo_build_season(
  uuid, text, text[], text[], text[], int, int, int, int, int, date, text[],
  uuid[], int, int, text[], text, text) from public, anon, authenticated;
revoke all on function public.demo_reset() from public, anon, authenticated;
