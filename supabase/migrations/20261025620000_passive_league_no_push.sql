-- Pasif turnuvalardan da hiçbir kullanıcıya bildirim gitmez (uygulama içi
-- liste dahil). push_send her bildirimde push_ref_is_demo'yu sorar; bu
-- kontrol artık demo VEYA pasif turnuvada true döner.
create or replace function public.league_push_muted(p_league_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select p_league_id is not null and (
    public.is_demo_league(p_league_id)
    or exists (select 1 from public.leagues l
                where l.id = p_league_id and l.status = 'passive')
  );
$$;

CREATE OR REPLACE FUNCTION public.push_ref_is_demo(p_kind text, p_ref text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_league uuid;
begin
  -- Etiketsiz Instagram gönderisi: approval-ig<news id>.
  if p_kind = 'approval' and p_ref ~* '^ig[0-9a-f-]{36}$' then
    select s.league_id into v_league
      from public.news n join public.seasons s on s.id = n.season_id
     where n.id = substr(p_ref, 3)::uuid;
    return public.league_push_muted(v_league);
  end if;
  -- Yayın linki uyuşmazlığı: yt-conflict-<id>.
  if p_kind = 'yt' and p_ref ~* '^conflict-[0-9a-f-]{36}$' then
    select c.league_id into v_league
      from public.youtube_link_conflicts c
     where c.id = substr(p_ref, 10)::uuid;
    return public.league_push_muted(v_league);
  end if;

  if p_ref is null or p_ref !~* '^[0-9a-f-]{36}$' then
    return false;
  end if;
  v_id := p_ref::uuid;
  if p_kind in ('reminder', 'schedule', 'live', 'goal', 'result', 'attend', 'esame') then
    select coalesce(m.league_id, s.league_id) into v_league
      from public.matches m left join public.seasons s on s.id = m.season_id
     where m.id = v_id;
  elsif p_kind = 'news' then
    select s.league_id into v_league
      from public.news n join public.seasons s on s.id = n.season_id
     where n.id = v_id;
  elsif p_kind in ('penalty', 'penaltyok') then
    select coalesce(m.league_id, s.league_id) into v_league
      from public.player_penalties pp
      left join public.matches m on m.id = pp.match_id
      left join public.seasons s on s.id = pp.season_id
     where pp.id = v_id;
  elsif p_kind in ('approval', 'roster') then
    select coalesce(pa.league_id, s.league_id) into v_league
      from public.pending_actions pa left join public.seasons s on s.id = pa.season_id
     where pa.id = v_id;
  end if;
  return public.league_push_muted(v_league);
exception when others then
  return false;
end;
$function$

;
