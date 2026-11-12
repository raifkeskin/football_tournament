-- Çift kayıt adayları: aynı ad (name), aynı telefon (phone) ve yaklaşık ad + aynı doğum yılı (similar).
drop function if exists public.admin_dup_candidates();
-- Adayları listeler. Her satır bir çift; a ve b kayıtlarının özeti jsonb.
create or replace function public.admin_dup_candidates()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare out jsonb;
begin
  if not public.is_admin() then raise exception 'Yetkiniz yok.'; end if;
  with info as (
    select p.id, p.name, p.surname, p.birth_date, p.phone, (p.auth_uid is not null) as has_acc,
           public.norm_person_name(p.name) || ' ' || public.norm_person_name(p.surname) as k,
           coalesce((select jsonb_agg(jsonb_build_object(
                'season_id', s.season_id, 'team', t.name, 'league', l.name, 'season', se.name)
              order by l.name)
              from public.season_team_players s
              join public.teams t on t.id = s.team_id
              join public.seasons se on se.id = s.season_id
              join public.leagues l on l.id = se.league_id
              where s.player_id = p.id), '[]'::jsonb) as rosters,
           (select count(*) from public.match_events e where e.player_id = p.id) as ev,
           p.created_at
    from public.players p
  ), pairs as (
    select a.id as a_id, b.id as b_id,
           to_jsonb(a) - 'k' as a, to_jsonb(b) - 'k' as b,
           coalesce((select jsonb_agg(jsonb_build_object(
                'season_id', x->>'season_id', 'season', x->>'season', 'league', x->>'league',
                'a_team', x->>'team', 'b_team', y->>'team',
                'open', public.roster_add_open((x->>'season_id')::uuid)))
              from jsonb_array_elements(a.rosters) x, jsonb_array_elements(b.rosters) y
              where x->>'season_id' = y->>'season_id'), '[]'::jsonb) as shared,
           case when a.k = b.k then 'name'
                when nullif(a.phone,'') is not null and a.phone = b.phone then 'phone'
                else 'similar' end as kind
    from info a join info b on a.id < b.id
      and (a.k = b.k
           or (nullif(a.phone,'') is not null and a.phone = b.phone)
           or (extract(year from a.birth_date) = extract(year from b.birth_date)
               and levenshtein(a.k, b.k) <= 2))
    where not exists (select 1 from public.player_dup_dismissed d where d.a = a.id and d.b = b.id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'a', pairs.a, 'b', pairs.b, 'shared', pairs.shared, 'kind', pairs.kind,
      'same_season', jsonb_array_length(pairs.shared) > 0,
      'transfer_open', jsonb_array_length(pairs.shared) > 0
        and not exists (select 1 from jsonb_array_elements(pairs.shared) z where (z->>'open')::boolean is not true),
      'both_accounts', (pairs.a->>'has_acc')::boolean and (pairs.b->>'has_acc')::boolean)
    order by pairs.a->>'name', pairs.a->>'surname'), '[]'::jsonb)
  into out from pairs;
  return out;
end $$;


revoke all on function public.admin_dup_candidates() from public, anon;
grant execute on function public.admin_dup_candidates() to authenticated;
