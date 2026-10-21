-- =====================================================================
-- Lig Masası · Supabase SQL Editor raporları
-- Kullanım: Supabase Dashboard → SQL Editor → New query. Bir bölümü
-- (iki çizgi arası) yapıştırın, Run deyin, sağ üstten "Save" ile adını
-- verin (ör. "01 Kayıt büyümesi"). Sonuç altında "Chart" ile grafiğe
-- çevirebilirsiniz. Sorguların hepsi yalnız OKUR; veri değiştirmez.
-- Demo ligler (is_demo) raporlardan çıkarılmıştır.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 01 · Kayıt büyümesi: son 30 gün, günlük yeni hesap ve misafir
-- ---------------------------------------------------------------------
select (created_at at time zone 'Europe/Istanbul')::date as gun,
       count(*) filter (where not is_anonymous) as yeni_hesap,
       count(*) filter (where is_anonymous)     as yeni_misafir
  from auth.users
 where created_at > now() - interval '30 days'
 group by 1
 order by 1 desc;


-- ---------------------------------------------------------------------
-- 02 · Kullanıcı özeti: toplam hesap, rol ve son giriş
-- ---------------------------------------------------------------------
select
  (select count(*) from auth.users where not is_anonymous)                       as hesap,
  (select count(*) from auth.users where is_anonymous)                           as misafir,
  (select count(*) from public.admins)                                           as admin,
  (select count(distinct user_id) from public.league_owners)                     as kurucu_baskan,
  (select count(distinct user_id) from public.region_owners)                     as bolge_sorumlusu,
  (select count(distinct user_id) from public.team_managers)                     as takim_sorumlusu,
  (select count(*) from public.players where auth_uid is not null)               as hesabi_bagli_futbolcu,
  (select count(*) from auth.users where not is_anonymous
      and last_sign_in_at > now() - interval '1 day')                            as son_24s_giris,
  (select count(*) from auth.users where not is_anonymous
      and last_sign_in_at > now() - interval '7 days')                           as son_7g_giris;


-- ---------------------------------------------------------------------
-- 03 · Turnuva sağlığı: güncel sezon başına takım, oyuncu, maç
-- ---------------------------------------------------------------------
select l.name                                                     as turnuva,
       s.name                                                     as sezon,
       (select count(*) from public.season_teams st where st.season_id = s.id) as takim,
       (select count(*) from public.season_team_players p
         where p.season_id = s.id and p.is_active)                 as aktif_oyuncu,
       count(m.id)                                                 as mac,
       count(m.id) filter (where m.status = 'finished')            as oynanan,
       count(m.id) filter (where m.status in ('notStarted', 'postponed')) as kalan,
       count(m.id) filter (where m.status <> 'finished'
         and m.match_date < (now() at time zone 'Europe/Istanbul')::date) as sonucu_girilmemis
  from public.leagues l
  -- Varsayılan sezon; işaretli değilse en yeni sezon.
  join lateral (
    select x.* from public.seasons x
     where x.league_id = l.id and x.deleted_at is null
     order by x.is_default desc, x.start_date desc nulls last, x.created_at desc
     limit 1
  ) s on true
  left join public.matches m on m.season_id = s.id and m.deleted_at is null
 where not coalesce(l.is_demo, false)
 group by l.name, s.id, s.name
 order by l.name;


-- ---------------------------------------------------------------------
-- 04 · Sonucu girilmemiş maçlar (tarihi geçmiş, bitmemiş)
-- ---------------------------------------------------------------------
select l.name as turnuva, m.match_date as tarih, m.match_time as saat,
       h.name as ev_sahibi, a.name as deplasman, m.status as durum
  from public.matches m
  join public.leagues l on l.id = m.league_id
  left join public.teams h on h.id = m.home_team_id
  left join public.teams a on a.id = m.away_team_id
 where m.deleted_at is null
   and m.status in ('notStarted', 'live', 'halftime')
   and m.match_date < (now() at time zone 'Europe/Istanbul')::date
   and not coalesce(l.is_demo, false)
 order by m.match_date desc;


-- ---------------------------------------------------------------------
-- 05 · Takım sorumlusu bağlantısı (güncel sezonlar)
--      bagli = hesabıyla giriş yapıp esame girebilir
-- ---------------------------------------------------------------------
select l.name as turnuva, t.name as takim,
       coalesce(nullif(t.manager_name, ''), '—') as sorumlu,
       case
         when exists (select 1 from public.team_managers tm
                       where tm.season_id = s.id and tm.team_id = t.id) then 'bağlı'
         when nullif(t.manager_name, '') is not null then 'kayıt bekleniyor'
         else 'sorumlu yok'
       end as durum
  from public.leagues l
  -- Varsayılan sezon; işaretli değilse en yeni sezon.
  join lateral (
    select x.* from public.seasons x
     where x.league_id = l.id and x.deleted_at is null
     order by x.is_default desc, x.start_date desc nulls last, x.created_at desc
     limit 1
  ) s on true
  join public.season_teams st on st.season_id = s.id
  join public.teams t on t.id = st.team_id
 where not coalesce(l.is_demo, false)
 order by l.name, durum desc, t.name;


-- ---------------------------------------------------------------------
-- 06 · Esame doluluğu: son 14 günde oynanan maçlarda ilk 11 girildi mi
-- ---------------------------------------------------------------------
with sides as (
  select m.id, l.name as turnuva, m.match_date, m.home_team_id as team_id,
         coalesce(s.starting_player_count, 11) as gereken
    from public.matches m
    join public.leagues l on l.id = m.league_id
    join public.seasons s on s.id = m.season_id
   where m.status = 'finished' and m.deleted_at is null
     and m.match_date > (now() at time zone 'Europe/Istanbul')::date - 14
     and not coalesce(l.is_demo, false)
  union all
  select m.id, l.name, m.match_date, m.away_team_id,
         coalesce(s.starting_player_count, 11)
    from public.matches m
    join public.leagues l on l.id = m.league_id
    join public.seasons s on s.id = m.season_id
   where m.status = 'finished' and m.deleted_at is null
     and m.match_date > (now() at time zone 'Europe/Istanbul')::date - 14
     and not coalesce(l.is_demo, false)
)
select sd.turnuva, sd.match_date as tarih, t.name as takim,
       count(r.id) filter (where r.is_starting) as ilk_11,
       count(r.id) filter (where not r.is_starting) as yedek,
       sd.gereken,
       case when count(r.id) filter (where r.is_starting) >= sd.gereken
            then 'tamam' else 'eksik' end as durum
  from sides sd
  join public.teams t on t.id = sd.team_id
  left join public.match_rosters r on r.match_id = sd.id and r.team_id = sd.team_id
 group by sd.turnuva, sd.match_date, t.name, sd.gereken
 order by sd.match_date desc, durum, t.name;


-- ---------------------------------------------------------------------
-- 07 · Telefon bildirimi erişimi (platforma göre)
-- ---------------------------------------------------------------------
select coalesce(platform, '?') as platform,
       count(*) as cihaz,
       count(distinct user_id) as kisi
  from public.push_subscriptions
 group by 1
 order by 2 desc;


-- ---------------------------------------------------------------------
-- 08 · Gönderilen bildirimler: son 7 gün, türe göre (uygulama içi liste)
-- ---------------------------------------------------------------------
select coalesce(kind, '?') as tur,
       count(*) as bildirim,
       count(distinct user_id) as kisi
  from public.notifications
 where created_at > now() - interval '7 days'
 group by 1
 order by 2 desc;


-- ---------------------------------------------------------------------
-- 09 · Yapay zekâ kullanımı ve maliyeti: aylık
-- ---------------------------------------------------------------------
select to_char(date_trunc('month', created_at at time zone 'Europe/Istanbul'), 'YYYY-MM') as ay,
       purpose as islem,
       count(*) as istek,
       count(distinct match_id) as mac,
       round(sum(cost_usd)::numeric, 3) as usd,
       round(sum(cost_try)::numeric, 2) as tl
  from public.ai_usage_log
 group by 1, 2
 order by 1 desc, 2;


-- ---------------------------------------------------------------------
-- 10 · Gol kesitleri: son 30 gün analizler (otomatik / elle)
-- ---------------------------------------------------------------------
select l.name as turnuva, m.match_date as tarih,
       h.name || ' – ' || a.name as mac,
       case when j.requested_by is null then 'otomatik' else 'elle' end as baslatan,
       j.status as durum, j.found as bulunan, j.cost_usd as usd,
       (select count(*) from public.match_highlights mh
         where mh.match_id = m.id and mh.status = 'approved') as yayinda,
       j.error as hata
  from public.match_highlight_jobs j
  join public.matches m on m.id = j.match_id
  join public.leagues l on l.id = m.league_id
  left join public.teams h on h.id = m.home_team_id
  left join public.teams a on a.id = m.away_team_id
 where j.started_at > now() - interval '30 days'
 order by j.started_at desc;


-- ---------------------------------------------------------------------
-- 11 · Turnuva talepleri: durum hunisi ve teklif görüntülenme
-- ---------------------------------------------------------------------
select r.status as durum,
       count(*) as talep,
       count(*) filter (where r.info_only) as bilgi_talebi,
       count(*) filter (where exists (select 1 from public.tournament_offers o
                                       where o.request_id = r.id)) as teklif_gonderilen,
       count(*) filter (where r.offer_viewed_at is not null) as teklifi_goren
  from public.tournament_requests r
 group by 1
 order by 2 desc;


-- ---------------------------------------------------------------------
-- 12 · Uygulama hataları: son 7 gün, en sık
-- ---------------------------------------------------------------------
select count as tekrar, platform, app_version as surum, screen as ekran,
       left(message, 140) as mesaj, last_seen as son_gorulme
  from public.app_errors
 where last_seen > now() - interval '7 days'
 order by count desc
 limit 30;


-- ---------------------------------------------------------------------
-- 13 · Geri bildirimler (Sorun Bildir / Öneri): son 30 gün
-- ---------------------------------------------------------------------
select created_at at time zone 'Europe/Istanbul' as zaman,
       coalesce(role, 'misafir') as rol, platform, app_version as surum,
       league_name as turnuva, left(message, 300) as mesaj
  from public.app_feedback
 where created_at > now() - interval '30 days'
 order by created_at desc;


-- ---------------------------------------------------------------------
-- 14 · Önümüzdeki 7 gün: günlük maç sayısı (maç günü yük planı)
-- ---------------------------------------------------------------------
select m.match_date as tarih,
       count(*) as mac,
       count(distinct m.league_id) as turnuva,
       min(m.match_time) as ilk_mac, max(m.match_time) as son_mac,
       count(*) filter (where exists (
         select 1 from public.match_media mm
          where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki')) as yayin_linkli
  from public.matches m
  join public.leagues l on l.id = m.league_id
 where m.deleted_at is null and m.status = 'notStarted'
   and m.match_date between (now() at time zone 'Europe/Istanbul')::date
                        and (now() at time zone 'Europe/Istanbul')::date + 7
   and not coalesce(l.is_demo, false)
 group by 1
 order by 1;


-- ---------------------------------------------------------------------
-- 15 · Veritabanı boyutu: en büyük 15 tablo
-- ---------------------------------------------------------------------
select relname as tablo,
       pg_size_pretty(pg_total_relation_size(relid)) as boyut,
       n_live_tup as satir
  from pg_stat_user_tables
 order by pg_total_relation_size(relid) desc
 limit 15;
