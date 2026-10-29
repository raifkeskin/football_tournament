-- Lisans listesi: Boşta filtresi kurucu başkan / bölge sorumlusuna da açık;
-- boştaki oyuncunun telefonu yalnız admine.
CREATE OR REPLACE FUNCTION public.license_list(p_filter jsonb DEFAULT '{}'::jsonb, p_q text DEFAULT ''::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_admin boolean := public.is_admin();
  v_roster text := coalesce(p_filter->>'roster', 'in');
  v_staff boolean := false;
  v_league text := coalesce(p_filter->>'league', 'all');
  v_profile text := coalesce(p_filter->>'profile', 'all');
  v_account text := coalesce(p_filter->>'account', 'all');
  v_kvkk text := coalesce(p_filter->>'kvkk', 'all');
  v_q text := public.tr_fold(trim(coalesce(p_q, '')));
  v_out jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('total', 0, 'rows', '[]'::jsonb);
  end if;
  -- Kurucu başkan / bölge sorumlusu: kendi kadroları + boştaki oyuncular
  -- (hiçbir etkin kadroda olmayan; başka turnuvadan gelebilecek).
  v_staff := exists (select 1 from public.league_owners where user_id = v_uid)
          or exists (select 1 from public.region_owners where user_id = v_uid);

  with act as (
    select s.id as season_id, l.id as league_id
      from public.seasons s
      join public.leagues l on l.id = s.league_id
     where s.deleted_at is null
       and coalesce(l.status, '') <> 'passive'
       and l.is_active is not false
  ),
  roster as (
    select stp.player_id, act.league_id, st.group_id
      from public.season_team_players stp
      join act on act.season_id = stp.season_id
      left join public.season_teams st
        on st.season_id = stp.season_id and st.team_id = stp.team_id
     where stp.player_id is not null
  ),
  vis as (
    select r.* from roster r
     where v_admin
        or exists (select 1 from public.league_owners lo
                    where lo.league_id = r.league_id and lo.user_id = v_uid)
        or exists (select 1 from public.groups g
                     join public.region_owners ro on ro.region_id = g.region_id
                    where g.id = r.group_id and ro.user_id = v_uid)
  ),
  latest as (
    select distinct on (c.player_id, c.consent_type)
           c.player_id, c.consent_type, c.granted, c.version
      from public.player_consents c
     order by c.player_id, c.consent_type, c.created_at desc
  ),
  kv as (
    select player_id, count(*) = 3 as complete
      from latest
     where consent_type in ('privacy_notice', 'health_data', 'health_declaration')
       and granted and version = public.current_consent_version()
     group by player_id
  ),
  base as (
    select p.id, p.name, p.surname, p.birth_date, p.preferred_foot,
           p.main_position, p.sub_position, p.photo_url,
           case when v_admin or exists (select 1 from vis v where v.player_id = p.id)
                then p.phone end as phone,
           p.height,
           p.weight, p.created_at, p.updated_at,
           exists (select 1 from roster r where r.player_id = p.id) as in_roster,
           coalesce((select array_agg(distinct v.league_id) from vis v
                      where v.player_id = p.id), '{}') as leagues,
           exists (select 1 from public.player_verifications pv
                    where pv.player_id = p.id) as verified,
           p.auth_uid is not null as has_account,
           coalesce(kv.complete, false) as kvkk,
           public.tr_fold(concat_ws(' ', p.name, p.surname)) as folded
      from public.players p
      left join kv on kv.player_id = p.id
     where v_admin or exists (select 1 from vis v where v.player_id = p.id)
        or (v_staff and not exists (select 1 from roster r where r.player_id = p.id))
  ),
  f as (
    select b.*,
      (v_roster = 'all' or (v_roster = 'in') = b.in_roster) as pr,
      (v_league = 'all' or v_league = any (b.leagues::text[])) as pl,
      (v_profile = 'all' or (v_profile = 'ver') = b.verified) as pp,
      (v_account = 'all' or (v_account = 'yes') = b.has_account) as pa,
      (v_kvkk = 'all' or (v_kvkk = 'ok') = b.kvkk) as pk,
      (v_q = '' or strpos(b.folded, v_q) > 0) as pq
    from base b
  )
  select jsonb_build_object(
    'total', (select count(*) from f where pr and pl and pp and pa and pk and pq),
    'rows', coalesce((
      select jsonb_agg(to_jsonb(x) - 'folded' - 'pr' - 'pl' - 'pp' - 'pa' - 'pk' - 'pq'
                       order by x.folded)
        from (select * from f where pr and pl and pp and pa and pk and pq
               order by folded offset greatest(p_offset, 0)
               limit least(greatest(p_limit, 0), 200)) x), '[]'::jsonb),
    'banner', (select jsonb_build_object(
                 'missing', count(*) filter (where not kvkk),
                 'no_account', count(*) filter (where not kvkk and not has_account))
               from base where in_roster),
    'leagues', coalesce((
      select jsonb_object_agg(l.id, l.name)
        from public.leagues l
       where l.id in (select distinct league_id from vis)), '{}'::jsonb),
    'facets', jsonb_build_object(
      'roster', (select jsonb_build_object(
          'in', count(*) filter (where in_roster),
          'free', count(*) filter (where not in_roster),
          'all', count(*))
        from f where pl and pp and pa and pk and pq),
      'league', coalesce((
          select jsonb_object_agg(k, n) from (
            select 'all' as k, count(*) as n from f where pr and pp and pa and pk and pq
            union all
            select lid::text, count(*) from f, unnest(f.leagues) lid
             where pr and pp and pa and pk and pq group by lid) z), '{}'::jsonb),
      'profile', (select jsonb_build_object(
          'all', count(*), 'ver', count(*) filter (where verified),
          'unv', count(*) filter (where not verified))
        from f where pr and pl and pa and pk and pq),
      'account', (select jsonb_build_object(
          'all', count(*), 'yes', count(*) filter (where has_account),
          'no', count(*) filter (where not has_account))
        from f where pr and pl and pp and pk and pq),
      'kvkk', (select jsonb_build_object(
          'all', count(*), 'ok', count(*) filter (where kvkk),
          'wait', count(*) filter (where not kvkk))
        from f where pr and pl and pp and pa and pq)
    )
  ) into v_out;
  return v_out;
end;
$function$;
