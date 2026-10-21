-- Gol kesitleri otomatik (2): maç bitince 5 dk sonra başlar. Hata verirse
-- (ör. YouTube yayını henüz kapanmamış) 15 dk arayla en fazla 3 deneme.
-- Kesitler match:<id> Broadcast konusuna da gider: maç detayı açık olanlar
-- yeni kesitleri hemen görür.

alter table public.highlights_auto_attempts
  add column if not exists tries int not null default 1;

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
       and m.updated_at between now() - interval '12 hours'
                            and now() - interval '5 minutes'
       and s.ai_clips_enabled is not false
       and not public.is_demo_league(m.league_id)
       and coalesce(m.home_score, 0) + coalesce(m.away_score, 0) > 0
       and exists (
         select 1 from public.match_media mm
          where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki'
            and mm.url ~* '(youtube\.com|youtu\.be)'
       )
       -- İlk deneme: hiç iş yok. Yeniden deneme: otomatik iş hata verdi.
       and (
         (a.match_id is null and j.match_id is null)
         or (a.tries < 3 and a.called_at < now() - interval '15 minutes'
             and j.status = 'error' and j.requested_by is null)
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
     limit 3
  loop
    insert into public.highlights_auto_attempts (match_id) values (r.id)
    on conflict (match_id) do update
      set tries = public.highlights_auto_attempts.tries + 1,
          called_at = now();
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

-- Maç detayındaki kesit listesi Broadcast'ten yenilenir (match:<id>).
drop trigger if exists broadcast_change on public.match_highlights;
create trigger broadcast_change
  after insert or update or delete on public.match_highlights
  for each row execute function public.broadcast_match_change();
