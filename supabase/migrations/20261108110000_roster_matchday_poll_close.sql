-- 1) Takım sorumlusu esameyi maç günü 00:00'dan (Türkiye saati) itibaren
--    girer; turnuvanın açılış süresi daha erkense o geçerli.
create or replace function public.match_roster_open_at(p_match_id uuid)
 returns timestamp with time zone
 language sql
 stable security definer
 set search_path to ''
as $function$
  select least(
           ((m.match_date + left(m.match_time, 5)::time)
             at time zone 'Europe/Istanbul')
           - make_interval(hours => coalesce(l.roster_open_hours, 1)),
           (m.match_date::timestamp at time zone 'Europe/Istanbul'))
  from public.matches m
  left join public.leagues l on l.id = m.league_id
  where m.id = p_match_id
    and m.match_date is not null
    and coalesce(m.match_time, '') ~ '^\d{1,2}:\d{2}'
$function$;

-- 2) Katılım anketi maç saatinden 3 saat önce kendiliğinden kapanır
--    (saat yoksa eski davranış: maç başlayana kadar açık).
create or replace function public.attendance_match_open(p_match_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id and m.deleted_at is null
      and m.status in ('notStarted', 'postponed')
      and (m.match_date is null
           or coalesce(m.match_time, '') !~ '^\d{1,2}:\d{2}'
           or now() < ((m.match_date + left(m.match_time, 5)::time)
                         at time zone 'Europe/Istanbul') - interval '3 hours')
  )
$function$;
