-- Sezon yönetimindeki "gruba takım ekle" seçicisi: admin tüm takımları görür;
-- diğerleri yalnızca bu turnuvanın herhangi bir sezonunda yer almış takımları
-- ve henüz hiçbir sezona bağlanmamış (yeni açılmış) takımları görür. Böylece
-- başka turnuvaların (gizli/demo dahil) takımları listelenmez.

create or replace function public.list_linkable_teams(p_season_id uuid)
returns setof public.teams
language sql
stable
security definer
set search_path to ''
as $$
  select t.*
  from public.teams t
  where public.is_admin()
     or (
       (public.owns_season(p_season_id)
        or exists (select 1 from public.groups g
                   where g.season_id = p_season_id
                     and public.owns_group(g.id)))
       and (
         exists (
           select 1 from public.season_teams st
           join public.seasons s on s.id = st.season_id
           where st.team_id = t.id
             and s.league_id = (select league_id from public.seasons
                                where id = p_season_id)
         )
         or not exists (
           select 1 from public.season_teams st where st.team_id = t.id
         )
       )
     )
  order by t.name
$$;

grant execute on function public.list_linkable_teams(uuid) to authenticated;
