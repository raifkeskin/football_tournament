-- Fikstür / puan durumu / istatistik açılışında seçilecek turnuva: kişinin
-- kendi turnuvaları (kadrosunda oynadığı, sorumlusu olduğu takımın, sahibi
-- olduğu, kodla takip ettiği) arasından en yakın tarihli oynanmamış maçı
-- olan. Maçı olmayanlarda öncelik: oyuncu > takım sorumlusu > sahip >
-- takipçi. Kendi turnuvası yoksa null (uygulama "varsayılan" turnuvayı seçer).
create or replace function public.my_preferred_league()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  with mine as (
    select s.league_id, 1 as pri
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    join public.seasons s on s.id = stp.season_id
    where p.auth_uid = auth.uid() and stp.is_active
    union all
    select s.league_id, 2
    from public.team_managers tm
    join public.seasons s on s.id = tm.season_id
    where tm.user_id = auth.uid()
    union all
    select o.league_id, 3 from public.league_owners o where o.user_id = auth.uid()
    union all
    select f.league_id, 4 from public.league_followers f where f.user_id = auth.uid()
  ),
  ranked as (
    select m.league_id,
           min(m.pri) as pri,
           (select min(x.match_date)
              from public.matches x
             where x.league_id = m.league_id
               and x.status = 'notStarted'
               and x.match_date >= current_date) as next_date
    from mine m
    where m.league_id is not null
    group by m.league_id
  )
  select league_id from ranked
  order by next_date nulls last, pri
  limit 1
$$;

revoke all on function public.my_preferred_league() from public, anon;
grant execute on function public.my_preferred_league() to authenticated;
