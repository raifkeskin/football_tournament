-- Maç önü "Sorumlular" afişi: iki takımın sorumlusunun adı ve fotoğrafı.
-- team_managers herkese açık değil; yalnız ad + fotoğraf döner (ikisi de
-- players'ta zaten herkese açık). Bir takımın birden çok sorumlusu varsa
-- fotoğraflı ve en eski kayıt seçilir.
create or replace function public.match_poster_managers(
  p_season_id uuid,
  p_team_ids uuid[]
)
returns table (team_id uuid, name text, photo_url text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (tm.team_id)
    tm.team_id,
    trim(concat_ws(' ', p.name, p.surname))::text,
    nullif(trim(p.photo_url), '')
  from public.team_managers tm
  join public.players p on p.auth_uid = tm.user_id
  where tm.season_id = p_season_id
    and tm.team_id = any (p_team_ids)
  order by tm.team_id,
    (nullif(trim(p.photo_url), '') is null),
    tm.created_at;
$$;

revoke all on function public.match_poster_managers(uuid, uuid[]) from public;
grant execute on function public.match_poster_managers(uuid, uuid[])
  to anon, authenticated;
