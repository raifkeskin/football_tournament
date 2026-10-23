-- Gol kesitleri otomatik tarama takvimi: maç bitiminden 10 dk sonra ilk
-- deneme, sonra 30 dk arayla (yayın kaydı hazır değilse vb.), 12 saate kadar.
-- Medya sekmesi "gol videoları hazırlanıyor" bilgisini highlights_auto_status
-- ile gösterir.

-- Maç otomatik taramaya uygun mu (yayın linki, dakikalı goller, YZ açık).
create or replace function public.highlights_auto_eligible(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.matches m
      join public.seasons s on s.id = m.season_id
     where m.id = p_match_id
       and m.status = 'finished'
       and m.deleted_at is null
       and m.updated_at > now() - interval '12 hours'
       and s.ai_clips_enabled is not false
       and not public.is_demo_league(m.league_id)
       and coalesce(m.home_score, 0) + coalesce(m.away_score, 0) > 0
       and exists (
         select 1 from public.match_media mm
          where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki'
            and mm.url ~* '(youtube\.com|youtu\.be)')
       and (select count(*) from public.match_events e
             where e.match_id = m.id and e.event_type = 'goal')
           = coalesce(m.home_score, 0) + coalesce(m.away_score, 0)
       and not exists (
         select 1 from public.match_events e
          where e.match_id = m.id and e.event_type = 'goal' and e.minute is null)
  )
$function$;
revoke all on function public.highlights_auto_eligible(uuid) from public, anon, authenticated;

-- 'running': analiz sürüyor; 'pending': otomatik tarama bekliyor (yayın
-- kaydı hazırlanıyor ya da yeniden denenecek); null: yok / bitti.
create or replace function public.highlights_auto_status(p_match_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select case
    when j.status = 'running' then 'running'
    when (j.match_id is null
          or (j.status = 'error' and j.requested_by is null))
         and coalesce(a.tries, 0) < 24
         and public.highlights_auto_eligible(p_match_id) then 'pending'
  end
  from (select p_match_id as id) x
  left join public.match_highlight_jobs j on j.match_id = x.id
  left join public.highlights_auto_attempts a on a.match_id = x.id
$function$;
grant execute on function public.highlights_auto_status(uuid) to anon, authenticated;

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
      left join public.match_highlight_jobs j on j.match_id = m.id
      left join public.highlights_auto_attempts a on a.match_id = m.id
     where m.status = 'finished'
       and m.updated_at < now() - interval '10 minutes'
       and m.updated_at > now() - interval '12 hours'
       -- Henüz analiz yok ya da otomatik analiz hata verdi.
       and (j.match_id is null
            or (j.status = 'error' and j.requested_by is null))
       and coalesce(a.tries, 0) < 24
       and (a.match_id is null or a.called_at < now() - interval '30 minutes')
       and public.highlights_auto_eligible(m.id)
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
