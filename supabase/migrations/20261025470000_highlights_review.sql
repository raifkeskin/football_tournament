-- Gol kesitleri: yayında bulunamayan gol sayısı ve kontrol gereken analiz.
alter table public.match_highlight_jobs
  add column if not exists missing int,
  add column if not exists needs_review boolean not null default false;

-- Belirsiz analizde (başlangıç tutmadı / gollerin yarısından azı bulundu)
-- maçın kurucu başkanlarına ve bölge sorumlularına bildirim. Yalnız
-- video-highlights (service_role) çağırır.
create or replace function public.highlights_review_notify(p_match_id uuid, p_text text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_users uuid[];
  v_title text;
begin
  select array_agg(distinct u) into v_users from (
    select lo.user_id as u
      from public.matches m
      join public.league_owners lo on lo.league_id = m.league_id
     where m.id = p_match_id
    union
    select ro.user_id
      from public.matches m
      join public.groups g on g.id = m.group_id
      join public.region_owners ro on ro.region_id = g.region_id
     where m.id = p_match_id
  ) x;
  if v_users is null then
    return;
  end if;
  select coalesce(th.name, '') || ' - ' || coalesce(ta.name, '') into v_title
    from public.matches m
    left join public.teams th on th.id = m.home_team_id
    left join public.teams ta on ta.id = m.away_team_id
   where m.id = p_match_id;
  perform public.push_send(
    v_users,
    'Gol kesitleri: kontrol gerekli',
    coalesce(v_title || ' · ', '') || p_text,
    '/',
    'clips-' || p_match_id
  );
end;
$function$;
revoke all on function public.highlights_review_notify(uuid, text) from public, anon, authenticated;
grant execute on function public.highlights_review_notify(uuid, text) to service_role;
