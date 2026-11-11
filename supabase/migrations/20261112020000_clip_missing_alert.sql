-- Onaylı gol kesiti olduğu hâlde MP4 (hikâye) 3 saat içinde üretilmediyse
-- admine Telegram ile bildirilir (Mac'teki üretim işi kapalı, indirme hatası
-- vb.). Maç başına bir mesaj; kesit başına bir kez.
alter table public.match_highlights
  add column if not exists clip_alerted_at timestamptz;

create or replace function public.clip_missing_alert()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_admins uuid[] := (select array_agg(user_id) from public.admins where user_id is not null);
  r record;
begin
  if v_admins is null then
    return;
  end if;
  for r in
    select h.match_id,
           th.name as hn, ta.name as an,
           count(*) as n,
           string_agg(distinct h.minute::text, ', ') as mins,
           max(left(coalesce(h.clip_error, ''), 120)) as err,
           max(h.clip_tries) as tries
      from public.match_highlights h
      join public.matches m on m.id = h.match_id
      join public.leagues lg on lg.id = m.league_id
      join public.teams th on th.id = m.home_team_id
      join public.teams ta on ta.id = m.away_team_id
     where h.kind = 'goal' and h.status = 'approved'
       and h.video_id !~ '^http'
       and h.story_url is null
       and h.clip_alerted_at is null
       and m.status = 'finished'
       and lg.status = 'active' and coalesce(lg.is_active, true)
       and coalesce(h.reviewed_at, h.created_at) < now() - interval '3 hours'
       and coalesce(h.reviewed_at, h.created_at) > now() - interval '21 days'
     group by h.match_id, th.name, ta.name
  loop
    perform public.telegram_notify(
      v_admins,
      '⚠️ Gol videosu (MP4) üretilmedi: ' || r.hn || ' – ' || r.an
        || E'\n' || r.n || ' gol (' || r.mins || E'. dk) 3 saattir bekliyor.'
        || case when r.tries >= 3 then E'\n3 deneme de başarısız.' else E'\nMac işi kapalı olabilir.' end
        || case when r.err <> '' then E'\nSon hata: ' || r.err else '' end);
    update public.match_highlights h
       set clip_alerted_at = now()
     where h.match_id = r.match_id and h.kind = 'goal' and h.status = 'approved'
       and h.story_url is null and h.clip_alerted_at is null;
  end loop;
end;
$$;
revoke all on function public.clip_missing_alert() from public, anon, authenticated;

select cron.unschedule('clip-missing-alert')
 where exists (select 1 from cron.job where jobname = 'clip-missing-alert');
select cron.schedule('clip-missing-alert', '*/15 * * * *',
                     'select public.clip_missing_alert()');
