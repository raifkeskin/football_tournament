-- Yönetim Masası (web paneli, ligmasasi.com/panel): seçilen günün maçları
-- ve sonucu girilmemiş geçmiş maçlar tek istekte. Yalnız kişinin yönettiği
-- maçlar döner (owns_match ile aynı kural: admin, turnuva sahibi, bölge
-- sorumlusu). Yetkisi olmayan kişi için can=false.

create or replace function public.desk_matches(p_date date)
returns jsonb
language sql
stable security definer
set search_path to ''
as $$
  with mine as (
    select m.*, coalesce(m.league_id, s.league_id) as lid, s.name as season_name,
           g.name as group_name
    from public.matches m
    join public.seasons s on s.id = m.season_id and s.deleted_at is null
    left join public.groups g on g.id = m.group_id
    where auth.uid() is not null
      and m.deleted_at is null
      and (g.id is null or g.deleted_at is null)
      and (
        public.is_admin()
        or public.owns_league(coalesce(m.league_id, s.league_id))
        or (g.region_id is not null and exists (
          select 1 from public.region_owners ro
          where ro.region_id = g.region_id and ro.user_id = auth.uid()
        ))
      )
      and (
        m.match_date = p_date
        or (m.status in ('notStarted', 'live', 'halftime')
            and m.match_date between current_date - 60 and current_date
            and m.match_time ~ '^\d{1,2}:\d{2}'
            and ((m.match_date + left(m.match_time, 5)::time)
                   at time zone 'Europe/Istanbul') < now() - interval '2 hours')
      )
  )
  select jsonb_build_object(
    'can', public.is_admin()
           or exists (select 1 from public.league_owners o where o.user_id = auth.uid())
           or exists (select 1 from public.region_owners r where r.user_id = auth.uid()),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'league_id', m.lid,
        'league', l.name,
        'season', m.season_name,
        'group', m.group_name,
        'week', m.week,
        'cup_round', m.cup_round,
        'date', m.match_date,
        'time', m.match_time,
        'status', m.status,
        'knockout', m.tiebreak is not null,
        'home', ht.name, 'home_logo', ht.logo_url,
        'away', at.name, 'away_logo', at.logo_url,
        'hs', m.home_score, 'as', m.away_score,
        'hp', m.home_pens, 'ap', m.away_pens,
        'overdue', m.match_date <> p_date
      ) order by l.name, m.match_date, m.match_time, ht.name)
      from mine m
      left join public.leagues l on l.id = m.lid
      left join public.teams ht on ht.id = m.home_team_id
      left join public.teams at on at.id = m.away_team_id
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.desk_matches(date) from public, anon;
grant execute on function public.desk_matches(date) to authenticated;
