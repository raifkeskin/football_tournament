-- Kadroya ekleme aramasında "Boşta" etiketi: verilen oyunculardan hiçbir
-- etkin turnuva kadrosunda olmayanlar (license_list ile aynı tanım).
create or replace function public.players_free_ids(p_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path to ''
as $$
  select p.id
    from unnest(p_ids) as p(id)
   where auth.uid() is not null
     and not exists (
       select 1
         from public.season_team_players stp
         join public.seasons s on s.id = stp.season_id
         join public.leagues l on l.id = s.league_id
        where stp.player_id = p.id
          and s.deleted_at is null
          and coalesce(l.status, '') <> 'passive'
          and l.is_active is not false)
$$;

revoke all on function public.players_free_ids(uuid[]) from public, anon;
grant execute on function public.players_free_ids(uuid[]) to authenticated;
