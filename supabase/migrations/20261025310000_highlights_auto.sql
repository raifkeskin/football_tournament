-- Gol kesitleri otomatik: maç bittikten (son düzenlemeden) 20 dk sonra,
-- yayın linki varsa ve gol kayıtları dakikalı ve skorla eşitse analiz
-- kendiliğinden başlar. Sezon tercihi: kesitler otomatik yayınlansın mı
-- (kapalıysa sorumlu kontrol edip onaylar). Bütçe sınırları aynen geçerli.

alter table public.seasons
  add column if not exists ai_clips_auto_publish boolean not null default true;

-- highlights_sync_secret ve anon_key (herkese açık anahtar; video-highlights
-- JWT doğrulaması için) kurulumda psql ile doldurulur.
insert into public.app_private_settings (key, value) values
  ('highlights_sync_secret', replace(gen_random_uuid()::text, '-', '')),
  ('anon_key', '')
on conflict (key) do nothing;

-- Her maç bir kez otomatik denenir (fonksiyon reddetse de tekrar çağrılmaz).
create table if not exists public.highlights_auto_attempts (
  match_id uuid primary key references public.matches (id) on delete cascade,
  called_at timestamptz not null default now()
);
alter table public.highlights_auto_attempts enable row level security;
revoke all on public.highlights_auto_attempts from anon, authenticated;

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
     where m.status = 'finished'
       and m.deleted_at is null
       and m.updated_at between now() - interval '12 hours'
                            and now() - interval '20 minutes'
       and s.ai_clips_enabled is not false
       and not public.is_demo_league(m.league_id)
       and coalesce(m.home_score, 0) + coalesce(m.away_score, 0) > 0
       and exists (
         select 1 from public.match_media mm
          where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki'
            and mm.url ~* '(youtube\.com|youtu\.be)'
       )
       and not exists (
         select 1 from public.match_highlight_jobs j where j.match_id = m.id
       )
       and not exists (
         select 1 from public.highlights_auto_attempts a where a.match_id = m.id
       )
       -- Gol kayıtları skorla eşit ve hepsi dakikalı (dakikasız tam tarama
       -- pahalı; onu yalnız admin elle başlatır).
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
    on conflict do nothing;
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
  perform cron.schedule('highlights-auto', '*/10 * * * *',
    'select public.highlights_auto_tick()');
end $$;
