-- Giriş yapan kişinin turnuvaları: uygulama giriş yapmış kullanıcıya
-- (admin hariç) yalnızca bunları gösterir. Kaynaklar: kadrosunda oynadığı
-- (oyuncu kaydı hesaba bağlı ya da hesabın telefonuyla eşleşen), sorumlusu
-- olduğu takım, sahibi olduğu turnuva, bölge sorumluluğu, gözlemcisi olduğu
-- maç, kodla takip.

create or replace function public.my_league_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select auth.uid() as uid,
           split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1) as raw
  ),
  ids as (
    select s.league_id
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    join public.seasons s on s.id = stp.season_id
    cross join me
    where coalesce(stp.is_active, true)
      and (p.auth_uid = me.uid
           or (me.raw ~ '^5[0-9]{9}$' and public.phone_raw10(p.phone) = me.raw))
    union
    select s.league_id
    from public.team_managers tm
    join public.seasons s on s.id = tm.season_id
    cross join me where tm.user_id = me.uid
    union
    select s.league_id
    from public.teams t
    join public.season_teams st on st.team_id = t.id
    join public.seasons s on s.id = st.season_id
    cross join me where t.manager_id = me.uid
    union
    select o.league_id from public.league_owners o, me where o.user_id = me.uid
    union
    select s.league_id
    from public.region_owners ro
    join public.season_regions r on r.id = ro.region_id
    join public.seasons s on s.id = r.season_id
    cross join me where ro.user_id = me.uid
    union
    select coalesce(m.league_id, s.league_id)
    from public.matches m
    left join public.seasons s on s.id = m.season_id
    cross join me where m.observer_id = me.uid
    union
    select f.league_id from public.league_followers f, me where f.user_id = me.uid
  )
  select coalesce(array_agg(distinct league_id), '{}')
  from ids where league_id is not null
$$;

revoke all on function public.my_league_ids() from public, anon;
grant execute on function public.my_league_ids() to authenticated;
