-- Saatlik tarama yarınki maçları da kapsar: YouTube'a bir gün önceden
-- planlanan yayın, en geç bir saat içinde maça bağlanır (önceden yalnızca
-- maçtan 30 dk önce).
create or replace function public.youtube_autolink_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
  v_now timestamptz := now();
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
  v_hourly boolean := extract(minute from now()) < 5;
begin
  if not exists (
    select 1
      from public.matches m
      join public.leagues l on l.id = m.league_id
     where l.youtube_live
       and nullif(trim(l.youtube_url), '') is not null
       and m.deleted_at is null
       and m.match_date between v_today - 2 and v_today + 1
       and (
         v_hourly
         or (
           m.match_time ~ '^\d{1,2}:\d{2}'
           and (m.match_date + substring(m.match_time from '^\d{1,2}:\d{2}')::time)
                 at time zone 'Europe/Istanbul'
               between v_now - interval '4 hours' and v_now + interval '30 minutes'
           and not exists (
             select 1 from public.match_media mm
              where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki'
           )
         )
       )
  ) then
    return;
  end if;
  select value into v_secret from public.app_private_settings
   where key = 'youtube_sync_secret';
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/youtube-autolink',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret', v_secret
    ),
    timeout_milliseconds := 60000
  );
exception when others then
  raise warning 'youtube_autolink_tick: %', sqlerrm;
end;
$$;

revoke all on function public.youtube_autolink_tick() from public, anon, authenticated;
