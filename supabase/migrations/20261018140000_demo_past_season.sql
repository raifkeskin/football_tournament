-- Demo ligleri geçmiş yılda (2025) ve tamamlanmış kurar: tüm maçlar
-- oynanmış, haberler sezon sonuna göre. Böylece gerçek (2026) sezonlarla
-- birlikte farklı yıllı sezon listeleri görülür.
--
--   select public.demo_reset();

CREATE OR REPLACE FUNCTION public.demo_reset()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c_user constant uuid := 'd0000000-0000-4000-8000-0000000000aa';
  c_phone constant text := '5000000000';
  c_password constant text := 'demo2026';
  c_l1 constant uuid := 'd0000000-0000-4000-8000-000000000001';
  c_l2 constant uuid := 'd0000000-0000-4000-8000-000000000002';
  c_l3 constant uuid := 'd0000000-0000-4000-8000-000000000003';
  c_crest constant text :=
    'https://qxdjebzszikeslobrozf.supabase.co/storage/v1/object/public/media/teams/demo/';
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
  -- Demo sezonları geçmiş bir yılda ve tamamlanmış (farklı yıllı sezonların
  -- listelenmesi görülsün): ilk haftalar cumartesi.
  c_m_first constant date := date '2025-09-06';  -- 7 hafta
  c_o_first constant date := date '2025-09-20';  -- 5 hafta
  c_s_first constant date := date '2025-09-13';  -- 7 hafta
  v_s1 uuid;
  v_s2 uuid;
  v_s3 uuid;
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
  where s.league_id in (c_l1, c_l2, c_l3)
    and not exists (
      select 1 from public.season_teams x
      join public.seasons y on y.id = x.season_id
      where x.team_id = st.team_id and y.league_id not in (c_l1, c_l2, c_l3));
  select coalesce(array_agg(distinct stp.player_id), '{}') into v_players
  from public.season_team_players stp
  join public.seasons s on s.id = stp.season_id
  where s.league_id in (c_l1, c_l2, c_l3)
    and not exists (
      select 1 from public.season_team_players x
      join public.seasons y on y.id = x.season_id
      where x.player_id = stp.player_id and y.league_id not in (c_l1, c_l2, c_l3));

  delete from public.matches where league_id in (c_l1, c_l2, c_l3)
    or season_id in (select id from public.seasons where league_id in (c_l1, c_l2, c_l3));
  delete from public.seasons where league_id in (c_l1, c_l2, c_l3);
  delete from public.teams where id = any(v_teams);
  delete from public.players where id = any(v_players) and auth_uid is null;
  delete from public.leagues where id in (c_l1, c_l2, c_l3);

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
     true, '#1D4ED8', '#F59E0B', 1),
    (c_l3, 'Demo Şirketler Halısaha Ligi', 'Demo Şirketler', true, true,
     '730417', true, '#0B3B5C', '#F97316', 1);
  insert into public.league_owners (league_id, user_id)
  values (c_l1, c_user), (c_l2, c_user), (c_l3, c_user);

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
    8, 11, 30, 5, 7, c_m_first,
    array['19:00', '20:00', '21:00', '22:00'],
    array['415c9143-c7d0-4539-a276-e413ecf25c23'::uuid,
          'c9dd6c7d-29fe-49b9-813c-d91524e7666d'::uuid],
    1976, 1988, c_names_adult, '4-4-2', c_stream);

  v_s2 := public._demo_build_season(
    c_l2, '2026-2027 Sezonu', null,
    array['A Grubu'],
    array['Yıldız Koleji', 'Bilim Ortaokulu', 'Deniz Anadolu Lisesi',
          'Çınar Koleji', 'Ufuk Ortaokulu', 'Gökkuşağı Koleji'],
    6, 7, 20, 5, 5, c_o_first,
    array['10:00', '11:00', '12:00'],
    array['5c305a3a-574a-410b-a555-2642e187044f'::uuid],
    2011, 2013, c_names_kid, '2-3-1', c_stream);

  -- Şirketler halısaha ligi: 7'li, 2x25 dk, bol oyuncu değişikliği.
  v_s3 := public._demo_build_season(
    c_l3, '2026-2027 Sezonu', null,
    array['Lig'],
    array['Kuzey Lojistik', 'Mavi Yazılım', 'Atlas İnşaat', 'Pusula Sigorta',
          'Zirve Enerji', 'Defne Gıda', 'Orion Bilişim', 'Ekin Tekstil'],
    8, 7, 25, 10, 7, c_s_first,
    array['19:00', '20:00', '21:00', '22:00'],
    array['114e5e54-cf08-44af-a97e-7c911c6641f9'::uuid],
    1984, 2000, c_names_adult, '2-3-1', c_stream);

  -- Armalar (tek şablon; tool/demo_crests.py ile üretilip media/teams/demo/ altına
  -- yüklendi) ve armayla uyumlu takım renkleri.
  update public.teams t
     set logo_url = c_crest || v.file || '.webp',
         first_color = v.c1, second_color = v.c2
    from (values
      ('Kuzey Yıldızları', 'kuzey-yildizlari', '#B91C1C', '#F5C542'),
      ('Galata Veteranlar', 'galata-veteranlar', '#1D4ED8', '#F5C542'),
      ('Bakırköy Dostluk', 'bakirkoy-dostluk', '#047857', '#F8FAFC'),
      ('Florya Kartalları', 'florya-kartallari', '#111827', '#E5E7EB'),
      ('Şişli Efsaneler', 'sisli-efsaneler', '#EA580C', '#1F2937'),
      ('Eyüp Sultanlar', 'eyup-sultanlar', '#6D28D9', '#F5C542'),
      ('Beylikdüzü Masterlar', 'beylikduzu-masterlar', '#BE185D', '#F8FAFC'),
      ('Haliç Spor', 'halic-spor', '#1E3A8A', '#38BDF8'),
      ('Moda Masterlar', 'moda-masterlar', '#CA8A04', '#1E293B'),
      ('Üsküdar Dostlar', 'uskudar-dostlar', '#334155', '#F59E0B'),
      ('Ataşehir Yıldızları', 'atasehir-yildizlari', '#15803D', '#FACC15'),
      ('Maltepe Sahil', 'maltepe-sahil', '#0369A1', '#F8FAFC'),
      ('Kartal Veteranlar', 'kartal-veteranlar', '#9F1239', '#F5C542'),
      ('Pendik Denizciler', 'pendik-denizciler', '#0F766E', '#F8FAFC'),
      ('Çekmeköy Kurtları', 'cekmekoy-kurtlari', '#C2410C', '#111827'),
      ('Beykoz Efsaneleri', 'beykoz-efsaneleri', '#4D7C0F', '#F5C542'),
      ('Yıldız Koleji', 'yildiz-koleji', '#B91C1C', '#F8FAFC'),
      ('Bilim Ortaokulu', 'bilim-ortaokulu', '#1D4ED8', '#FACC15'),
      ('Deniz Anadolu Lisesi', 'deniz-anadolu-lisesi', '#0E7490', '#F8FAFC'),
      ('Çınar Koleji', 'cinar-koleji', '#166534', '#FACC15'),
      ('Ufuk Ortaokulu', 'ufuk-ortaokulu', '#EA580C', '#F8FAFC'),
      ('Gökkuşağı Koleji', 'gokkusagi-koleji', '#7C3AED', '#FDE047'),
      ('Kuzey Lojistik', 'kuzey-lojistik', '#1E40AF', '#F97316'),
      ('Mavi Yazılım', 'mavi-yazilim', '#0284C7', '#F8FAFC'),
      ('Atlas İnşaat', 'atlas-insaat', '#B45309', '#111827'),
      ('Pusula Sigorta', 'pusula-sigorta', '#0F766E', '#FACC15'),
      ('Zirve Enerji', 'zirve-enerji', '#DC2626', '#F8FAFC'),
      ('Defne Gıda', 'defne-gida', '#15803D', '#F8FAFC'),
      ('Orion Bilişim', 'orion-bilisim', '#4C1D95', '#22D3EE'),
      ('Ekin Tekstil', 'ekin-tekstil', '#BE123C', '#F5C542')
    ) v(name, file, c1, c2)
   where t.name = v.name
     and t.id in (select st.team_id from public.season_teams st
                  where st.season_id in (v_s1, v_s2, v_s3));

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
  where m.season_id = v_s1 and m.week = 7 and g.region_id = v_r1;
  insert into public.news (season_id, region_id, content, is_published, created_at)
  values (v_s1, v_r1,
    'AVRUPA GRUBUNDA SEZON TAMAMLANDI' || E'\n\n' || v_txt || E'\n\n' ||
    'Avrupa Grubu''nda son hafta da oynandı. Final puan durumu ve gol '
    || 'krallığı uygulamada. Tüm takımlarımıza teşekkürler!',
    true, (c_m_first + 43)::timestamp + interval '10 hours');

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  join public.groups g on g.id = m.group_id
  where m.season_id = v_s1 and m.week = 7 and g.region_id = v_r2;
  insert into public.news (season_id, region_id, content, is_published, created_at)
  values (v_s1, v_r2,
    'ANADOLU GRUBUNDA SON HAFTA SONUÇLARI' || E'\n\n' || v_txt || E'\n\n' ||
    'Anadolu Grubu''nda sezon sona erdi. Maç özetleri ve kadrolar için maç '
    || 'detaylarına göz atabilirsiniz.',
    true, (c_m_first + 43)::timestamp + interval '11 hours');

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
  insert into public.news (season_id, content, is_published, created_at)
  values (v_s1,
    'GOL KRALLIĞI' || E'\n\n' || 'Sezon sonunda gol '
    || 'krallığında ' || v_txt || '. Sezonun en gollü maçı ise '
    || v_txt2 || ' karşılaşması oldu.',
    true, (c_m_first + 44)::timestamp + interval '9 hours');

  insert into public.news (season_id, content, is_published, created_at)
  values (v_s1,
    'YENİ SEZON HAZIRLIKLARI' || E'\n\n' || 'Yeni sezonun kayıtları '
    || 'yakında açılacak. Takım sorumluları kadrolarını uygulamadan '
    || 'güncelleyebilir; esameler maç saatinden 1 saat önce girilir.',
    true, (c_m_first + 50)::timestamp + interval '12 hours');

  insert into public.news (season_id, content, is_published, created_at)
  values (v_s1,
    'FAIR PLAY ÇAĞRISI' || E'\n\n' || 'Ligimizde dostluk ve centilmenlik '
    || 'her şeyden önce gelir. Hakem kararlarına saygı gösteren, rakibine '
    || 'yardım eden tüm oyuncularımıza teşekkür ederiz.',
    true, (c_m_first + 18)::timestamp + interval '15 hours');

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  where m.season_id = v_s2 and m.week = 5;
  insert into public.news (season_id, content, is_published, created_at)
  values (v_s2,
    'OKUL KUPASI TAMAMLANDI' || E'\n\n' || v_txt || E'\n\n' ||
    'Öğrencilerimize ve onları destekleyen ailelere teşekkür ederiz.',
    true, (c_o_first + 29)::timestamp + interval '13 hours');
  insert into public.news (season_id, content, is_published, created_at)
  values (v_s2,
    'OKUL KUPASI BAŞLADI' || E'\n\n' || 'Altı okulun katıldığı turnuvamız '
    || 'başladı. Maç programı, kadrolar ve sonuçlar uygulamada.',
    true, (c_o_first - 1)::timestamp + interval '10 hours');

  select string_agg(h.name || ' ' || m.home_score || '-' || m.away_score || ' ' || a.name,
                    E'\n' order by m.match_time)
    into v_txt
  from public.matches m
  join public.teams h on h.id = m.home_team_id
  join public.teams a on a.id = m.away_team_id
  where m.season_id = v_s3 and m.week = 7;
  insert into public.news (season_id, content, is_published, created_at)
  values (v_s3,
    'ŞİRKETLER LİGİNDE SON HAFTA' || E'\n\n' || v_txt || E'\n\n' ||
    'Sezon tamamlandı. Final puan durumu ve gol krallığı uygulamada.',
    true, (c_s_first + 43)::timestamp + interval '9 hours');
  insert into public.news (season_id, content, is_published, created_at)
  values (v_s3,
    'ŞİRKETLER HALISAHA LİGİ BAŞLADI' || E'\n\n' || 'Sekiz şirket takımı '
    || 'iş çıkışı halısahada karşı karşıya. 7''li maçlar, 2x25 dakika. '
    || 'Fikstür, kadrolar ve canlı skor uygulamada.',
    true, (c_s_first - 1)::timestamp + interval '18 hours');

  alter table public.matches enable trigger matches_push_notify;
  alter table public.news enable trigger news_push_notify;

  return jsonb_build_object(
    'leagues', array[c_l1, c_l2, c_l3],
    'login', c_phone, 'password', c_password,
    'matches', (select count(*) from public.matches where league_id in (c_l1, c_l2, c_l3)),
    'events', (select count(*) from public.match_events e
               join public.matches m on m.id = e.match_id
               where m.league_id in (c_l1, c_l2, c_l3)),
    'penalties', (select count(*) from public.player_penalties pp
                  where pp.season_id in (v_s1, v_s2, v_s3)));
end;
$function$;

revoke all on function public.demo_reset() from public, anon, authenticated;
