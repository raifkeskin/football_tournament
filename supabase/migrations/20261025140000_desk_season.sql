-- Yönetim Masası: Fikstür, Puan Durumu, Takımlar, Lisanslar, Cezalar,
-- Sponsorlar ve Haberler aynı sezon verisini paylaşır; tek istekte gelir.
-- Yalnız turnuvanın sorumluları (admin, turnuva sahibi, turnuvada bölgesi
-- olan bölge sorumlusu). Değişiklikler mevcut RLS kurallarıyla yazılır.

create or replace function public.desk_season(p_league_id uuid, p_season_id uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_season uuid;
  r jsonb;
begin
  if not (public.is_admin() or public.owns_league(p_league_id) or exists (
    select 1 from public.region_owners ro
      join public.season_regions sr on sr.id = ro.region_id
      join public.seasons s on s.id = sr.season_id
     where s.league_id = p_league_id and ro.user_id = auth.uid())) then
    raise exception 'Bu turnuvayı yönetme yetkiniz yok.' using errcode = '42501';
  end if;

  -- Seçilmediyse: varsayılan, yoksa aktif, yoksa en yeni sezon.
  select s.id into v_season
    from public.seasons s
   where s.league_id = p_league_id and s.deleted_at is null
     and (p_season_id is null or s.id = p_season_id)
   order by (s.id = p_season_id) desc nulls last, s.is_default desc nulls last,
            s.is_active desc nulls last, s.created_at desc
   limit 1;

  select jsonb_build_object(
    'season_id', v_season,
    'seasons', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'active', s.is_active)
                       order by s.created_at desc)
      from public.seasons s where s.league_id = p_league_id and s.deleted_at is null
    ), '[]'::jsonb),
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name) order by g.name)
      from public.groups g where g.season_id = v_season and g.deleted_at is null
    ), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'logo', t.logo_url, 'group_id', st.group_id,
        'managers', (select string_agg(coalesce(nullif(u.display_name, ''), u.name), ', ')
                       from public.team_managers tm
                       left join public.app_users u on u.auth_uid = tm.user_id::text
                      where tm.season_id = v_season and tm.team_id = t.id)
      ) order by t.name)
      from public.season_teams st join public.teams t on t.id = st.team_id
      where st.season_id = v_season
    ), '[]'::jsonb),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'team_id', stp.team_id,
        'name', trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
        'no', stp.jersey_number, 'birth_year', p.birth_year,
        'pos', p.main_position, 'photo', p.photo_url
      ) order by p.name, p.surname)
      from public.season_team_players stp
      join public.players_public p on p.id = stp.player_id
      where stp.season_id = v_season and coalesce(stp.is_active, true)
    ), '[]'::jsonb),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'week', m.week, 'group_id', m.group_id, 'date', m.match_date,
        'time', m.match_time, 'pitch_id', m.pitch_id, 'status', m.status,
        'hs', m.home_score, 'as', m.away_score, 'knockout', m.tiebreak is not null,
        'cup_round', m.cup_round, 'home_id', m.home_team_id, 'away_id', m.away_team_id
      ) order by m.week nulls last, m.match_date nulls last, m.match_time)
      from public.matches m
      where m.season_id = v_season and m.deleted_at is null
    ), '[]'::jsonb),
    'pitches', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name) order by p.name)
      from public.pitches p
    ), '[]'::jsonb),
    'penalties', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pe.id, 'player', trim(coalesce(pl.name, '') || ' ' || coalesce(pl.surname, '')),
        'player_id', pe.player_id, 'kind', pe.kind, 'status', pe.status,
        'match_count', pe.match_count, 'remaining', pe.remaining_matches,
        'active', pe.is_active, 'reason', pe.penalty_reason, 'created_at', pe.created_at,
        'match_id', pe.match_id
      ) order by pe.created_at desc)
      from public.player_penalties pe
      left join public.players_public pl on pl.id = pe.player_id
      where pe.season_id = v_season
    ), '[]'::jsonb),
    'sponsors', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sp.id, 'name', sp.name, 'logo', sp.logo_url, 'tier', sp.tier,
        'link', sp.link_url, 'active', sp.is_active, 'sort', sp.sort_order,
        'style', sp.name_style
      ) order by sp.tier, sp.sort_order nulls last, sp.name)
      from public.sponsors sp where sp.league_id = p_league_id
    ), '[]'::jsonb),
    'news', coalesce((
      select jsonb_agg(x order by (x->>'created_at') desc) from (
        select jsonb_build_object(
          'id', n.id, 'content', n.content, 'image', n.image_url,
          'published', n.is_published, 'created_at', n.created_at, 'auto', n.auto_kind
        ) x
        from public.news n
        join public.seasons s on s.id = n.season_id
        where s.league_id = p_league_id and coalesce(n.auto_hidden, false) = false
        order by n.created_at desc limit 60
      ) q
    ), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;

revoke all on function public.desk_season(uuid, uuid) from public, anon;
grant execute on function public.desk_season(uuid, uuid) to authenticated;
