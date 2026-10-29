-- Gol kesitleri otomatik tarama: teşhis ve takvim.
-- 1) Her denemenin hatası silinmeyen highlight_attempt_log tablosuna yazılır
--    (match_highlight_jobs tek satır; yeni deneme eski hatayı siliyordu).
-- 2) YouTube canlı yayın kaydını işlemeyi uzun yayınlarda saatler sürebilir:
--    ilk deneme maç bitiminden 1 saat sonra, sonra saatte bir, 24 saate kadar.
-- 3) Denemeler tükenirse adminlere Telegram'dan son hatayla haber verilir.

create table if not exists public.highlight_attempt_log (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  at timestamptz not null default now(),
  auto boolean not null default true,
  stage text not null,
  status int,
  error text
);
create index if not exists highlight_attempt_log_match_idx
  on public.highlight_attempt_log (match_id, at desc);
alter table public.highlight_attempt_log enable row level security;
revoke all on public.highlight_attempt_log from anon, authenticated;

alter table public.highlights_auto_attempts
  add column if not exists notified_at timestamptz;

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
       and m.updated_at > now() - interval '24 hours'
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
       and m.updated_at < now() - interval '60 minutes'
       and m.updated_at > now() - interval '24 hours'
       -- Henüz analiz yok ya da otomatik analiz hata verdi.
       and (j.match_id is null
            or (j.status = 'error' and j.requested_by is null))
       and coalesce(a.tries, 0) < 24
       and (a.match_id is null or a.called_at < now() - interval '60 minutes')
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

  -- Denemeler tükendi (24 deneme ya da 24 saat) ve kesit yok: adminlere
  -- son hatayla bir kez haber.
  for r in
    select a.match_id,
           coalesce(th.name, '') || ' - ' || coalesce(ta.name, '') as title,
           a.tries,
           (select coalesce(l.stage || ': ', '') || coalesce(l.error, '')
              from public.highlight_attempt_log l
             where l.match_id = a.match_id
             order by l.at desc limit 1) as last_error
      from public.highlights_auto_attempts a
      join public.matches m on m.id = a.match_id
      left join public.teams th on th.id = m.home_team_id
      left join public.teams ta on ta.id = m.away_team_id
      left join public.match_highlight_jobs j on j.match_id = a.match_id
     where a.notified_at is null
       and (a.tries >= 24 or m.updated_at < now() - interval '24 hours')
       and m.updated_at > now() - interval '48 hours'
       and (j.match_id is null or j.status = 'error')
     limit 5
  loop
    update public.highlights_auto_attempts set notified_at = now()
     where match_id = r.match_id;
    begin
      perform public.telegram_notify(
        array(select user_id from public.admins where user_id is not null),
        '⚠️ Gol kesitleri otomatik alınamadı' || E'\n' || r.title
          || E'\n' || r.tries || ' deneme'
          || coalesce(E'\nSon hata: ' || left(r.last_error, 300), '')
          || E'\nMaç detayı › Medya''dan elle başlatabilirsin.'
      );
    exception when others then
      raise warning 'highlights_auto_tick telegram: %', sqlerrm;
    end;
  end loop;
end;
$function$;
