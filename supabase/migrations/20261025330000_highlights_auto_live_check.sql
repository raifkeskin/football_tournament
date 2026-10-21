-- Gol kesitleri otomatik (3): maç "bitti" olunca dakikada bir video-highlights
-- çağrılır. Fonksiyon YouTube'a yayının bitip bitmediğini sorar (videos.list,
-- 1 kota birimi): sürüyorsa bekler, bittiyse analizi hemen başlatır ve
-- denemeyi sayar (tries). Hata verirse 15 dk arayla en fazla 3 deneme.
-- Yayın 30 dk içinde kapanmazsa beklemekten vazgeçilir; analizi sorumlu
-- maç detayından elle başlatır.

alter table public.highlights_auto_attempts alter column tries set default 0;

create or replace function public.highlights_auto_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_secret text;
  v_anon text;
  r record;
begin
  select value into v_secret from public.app_private_settings
   where key = 'highlights_sync_secret';
  select value into v_anon from public.app_private_settings
   where key = 'anon_key';
  if coalesce(v_secret, '') = '' or coalesce(v_anon, '') = '' then
    return;
  end if;

  for r in
    select m.id
      from public.matches m
      join public.seasons s on s.id = m.season_id
      left join public.match_highlight_jobs j on j.match_id = m.id
      left join public.highlights_auto_attempts a on a.match_id = m.id
     where m.status = 'finished'
       and m.deleted_at is null
       and m.updated_at > now() - interval '12 hours'
       and s.ai_clips_enabled is not false
       and not public.is_demo_league(m.league_id)
       and coalesce(m.home_score, 0) + coalesce(m.away_score, 0) > 0
       and exists (
         select 1 from public.match_media mm
          where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki'
            and mm.url ~* '(youtube\.com|youtu\.be)'
       )
       and (
         -- Henüz analiz yok: yayın bitene kadar dakikada bir sorulur.
         (j.match_id is null
          and m.updated_at > now() - interval '30 minutes'
          -- Fonksiyon analizden önce reddediyorsa (ör. bütçe) 3 kez denenir.
          and coalesce(a.tries, 0) < 3
          and (a.match_id is null or a.called_at < now() - interval '50 seconds'))
         -- Otomatik analiz hata verdi: 15 dk sonra yeniden (en fazla 3).
         or (j.status = 'error' and j.requested_by is null
             and coalesce(a.tries, 0) < 3
             and coalesce(j.finished_at, j.started_at) < now() - interval '15 minutes'
             and (a.match_id is null or a.called_at < now() - interval '50 seconds'))
       )
       and (
         select count(*) from public.match_events e
          where e.match_id = m.id and e.event_type = 'goal'
       ) = coalesce(m.home_score, 0) + coalesce(m.away_score, 0)
       and not exists (
         select 1 from public.match_events e
          where e.match_id = m.id and e.event_type = 'goal' and e.minute is null
       )
     order by m.updated_at
     limit 5
  loop
    insert into public.highlights_auto_attempts (match_id, tries, called_at)
    values (r.id, 0, now())
    on conflict (match_id) do update set called_at = now();
    perform net.http_post(
      url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/video-highlights',
      body := jsonb_build_object('match_id', r.id, 'auto', true),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_anon,
        'x-sync-secret', v_secret
      ),
      timeout_milliseconds := 30000
    );
  end loop;
end;
$function$;

revoke all on function public.highlights_auto_tick() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'highlights-auto') then
    perform cron.unschedule('highlights-auto');
  end if;
  perform cron.schedule('highlights-auto', '* * * * *',
    'select public.highlights_auto_tick()');
end $$;
