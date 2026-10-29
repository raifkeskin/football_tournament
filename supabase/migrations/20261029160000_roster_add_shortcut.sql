-- Kadroya Futbolcu Ekle kısayolu (takım sorumlusu menüsü).
-- Yalnız admin + deneme hesapları görür (roster_add_shortcut_enabled /
-- roster_add_shortcut_users); herkese açılınca anahtar true yapılır.
--   my_roster_add_targets(): sorumlusu olduğum takım × turnuva (son sezon)
--   roster_add_candidates(): bu sezonun kadrolarında olmayan futbolcular
--     (boşta ya da başka turnuvada), arama / durum / mevki / kimlik filtresi
--   identity_add_to_season_roster(): kimlik okutarak ekleme, maçtan bağımsız

insert into public.app_settings (key, value) values
  ('roster_add_shortcut_enabled', 'false'::jsonb),
  ('roster_add_shortcut_users', '[]'::jsonb)
on conflict (key) do nothing;

create or replace function public.my_roster_add_targets()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  with latest as (
    select distinct on (s.league_id) s.id, s.league_id, s.season_year
      from public.seasons s
      join public.leagues l on l.id = s.league_id
     where s.deleted_at is null
       and l.is_active is not false
       and coalesce(l.status, '') <> 'passive'
     order by s.league_id, s.season_year desc, s.start_date desc nulls last
  ), mine as (
    select st.season_id, st.team_id
      from public.season_teams st
      join latest x on x.id = st.season_id
     where auth.uid() is not null
       and (public.is_admin()
            or public.manages_team(st.season_id, st.team_id)
            or public.attendance_is_manager(st.season_id, st.team_id))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'season_id', m.season_id,
           'team_id', m.team_id,
           'team_name', t.name,
           'logo_url', t.logo_url,
           'first_color', t.first_color,
           'second_color', t.second_color,
           'league_name', l.name,
           'season_year', x.season_year,
           'roster_count', (select count(*) from public.season_team_players p
                             where p.season_id = m.season_id
                               and p.team_id = m.team_id and p.is_active),
           'add_open', public.roster_add_allowed(m.season_id)
         ) order by l.name, t.name), '[]'::jsonb)
    from mine m
    join latest x on x.id = m.season_id
    join public.leagues l on l.id = x.league_id
    join public.teams t on t.id = m.team_id
$$;

revoke all on function public.my_roster_add_targets() from public, anon;
grant execute on function public.my_roster_add_targets() to authenticated;

create or replace function public.roster_add_candidates(
  p_season_id uuid,
  p_team_id uuid,
  p_q text default null,
  p_status text default 'all',
  p_positions text[] default null,
  p_verified boolean default false,
  p_offset int default 0,
  p_limit int default 40
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_words text[];
  v_res jsonb;
begin
  if not (public.is_admin()
          or public.owns_season_team(p_season_id, p_team_id)
          or public.manages_team(p_season_id, p_team_id)
          or public.attendance_is_manager(p_season_id, p_team_id)) then
    raise exception 'Bu takıma oyuncu ekleme yetkiniz yok.';
  end if;
  v_words := array_remove(regexp_split_to_array(
    public.tr_fold(trim(coalesce(p_q, ''))), '\s+'), '');

  with base as (
    select p.id, p.name, p.surname, p.birth_date, p.main_position, p.photo_url,
           exists (select 1 from public.player_verifications v
                    where v.player_id = p.id) as verified,
           (select l.name
              from public.season_team_players o
              join public.seasons s on s.id = o.season_id
              join public.leagues l on l.id = s.league_id
             where o.player_id = p.id and o.is_active
               and s.deleted_at is null
               and l.is_active is not false
               and coalesce(l.status, '') <> 'passive'
             order by s.season_year desc, l.name
             limit 1) as other_league
      from public.players p
     where not exists (
             select 1 from public.season_team_players c
              where c.season_id = p_season_id and c.player_id = p.id
                and c.is_active)
       and not exists (
             select 1 from unnest(v_words) w
              where position(w in public.tr_fold(p.name || ' ' || p.surname)) = 0)
       and (coalesce(cardinality(p_positions), 0) = 0
            or p.main_position = any(p_positions))
       and (not p_verified or exists (
             select 1 from public.player_verifications v where v.player_id = p.id))
  ), filtered as (
    select * from base
     where p_status = 'all'
        or (p_status = 'free' and other_league is null)
        or (p_status = 'other' and other_league is not null)
  )
  select jsonb_build_object(
    'counts', jsonb_build_object(
      'all', (select count(*) from base),
      'free', (select count(*) from base where other_league is null),
      'other', (select count(*) from base where other_league is not null)),
    'total', (select count(*) from filtered),
    'rows', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.name, r.surname)
        from (select * from filtered
               order by name, surname
               offset greatest(p_offset, 0)
               limit least(greatest(p_limit, 1), 100)) r), '[]'::jsonb))
  into v_res;
  return v_res;
end;
$$;

revoke all on function public.roster_add_candidates(uuid, uuid, text, text, text[], boolean, int, int) from public, anon;
grant execute on function public.roster_add_candidates(uuid, uuid, text, text, text[], boolean, int, int) to authenticated;

CREATE OR REPLACE FUNCTION public.identity_add_to_season_roster(p_season_id uuid, p_team_id uuid, p_first text, p_last text, p_birth date, p_tc text, p_player_id uuid DEFAULT NULL::uuid, p_jersey smallint DEFAULT NULL::smallint, p_display text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_staff boolean;
  v_hash text;
  v_player uuid := p_player_id;
  v_first text := initcap(lower(trim(p_first)));
  v_last text := initcap(lower(trim(p_last)));
  v_disp text[];
  v_cur public.season_team_players;
  v_name text;
begin
  perform public._identity_guard(p_tc);
  if not exists (select 1 from public.season_teams
                  where season_id = p_season_id and team_id = p_team_id) then
    raise exception 'Takım bu turnuvada değil.';
  end if;
  v_staff := public.owns_season_team(p_season_id, p_team_id);
  if not v_staff and not public.attendance_is_manager(p_season_id, p_team_id) then
    raise exception 'Bu takıma oyuncu ekleme yetkiniz yok.';
  end if;
  v_hash := public._identity_hash(p_tc);

  if v_player is not null then
    -- Seçilen mevcut profil kimlikle onaylanır (kurallar identity_verify'da).
    perform public.identity_verify(v_player, p_first, p_last, p_birth, p_tc);
  else
    select player_id into v_player
      from public.player_verifications where tc_hash = v_hash;
    if v_player is null then
      -- Çip adı Türkçe harf taşımaz; kağıttaki yazım aynı harflerse o kullanılır.
      v_disp := regexp_split_to_array(trim(coalesce(p_display, '')), '\s+');
      if array_length(v_disp, 1) >= 2
         and public._id_fold(array_to_string(v_disp[1:array_length(v_disp, 1) - 1], ' '))
             = public._id_fold(trim(p_first))
         and public._id_fold(v_disp[array_length(v_disp, 1)]) = public._id_fold(trim(p_last)) then
        v_first := array_to_string(v_disp[1:array_length(v_disp, 1) - 1], ' ');
        v_last := v_disp[array_length(v_disp, 1)];
      end if;
      insert into public.players (name, surname, birth_date)
      values (v_first, v_last, p_birth)
      returning id into v_player;
      insert into public.player_verifications (player_id, tc_hash, verified_by)
      values (v_player, v_hash, auth.uid());
      insert into public.identity_events (player_id, action, user_id)
      values (v_player, 'create', auth.uid()), (v_player, 'verify', auth.uid());
    end if;
  end if;

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_name
    from public.players where id = v_player;

  select * into v_cur from public.season_team_players
   where season_id = p_season_id and player_id = v_player
   order by is_active desc limit 1;
  if found and v_cur.is_active and v_cur.team_id <> p_team_id then
    raise exception '% bu sezon başka bir takımda kayıtlı.', v_name;
  end if;
  if found and v_cur.is_active then
    return jsonb_build_object('status', 'added', 'player_id', v_player, 'name', v_name);
  end if;

  if v_staff then
    if found then
      update public.season_team_players
         set team_id = p_team_id, is_active = true,
             jersey_number = coalesce(p_jersey, jersey_number)
       where id = v_cur.id;
    else
      insert into public.season_team_players (season_id, team_id, player_id, jersey_number, is_active)
      values (p_season_id, p_team_id, v_player, p_jersey, true);
    end if;
    return jsonb_build_object('status', 'added', 'player_id', v_player, 'name', v_name);
  end if;

  insert into public.pending_actions (action_type, season_id, team_id, payload)
  values ('roster_add', p_season_id, p_team_id, jsonb_build_object(
    'player_id', v_player, 'player_name', v_name,
    'jersey_number', p_jersey, 'via', 'identity'))
  on conflict do nothing;
  return jsonb_build_object('status', 'pending', 'player_id', v_player, 'name', v_name);
end;
$function$;

revoke all on function public.identity_add_to_season_roster(uuid, uuid, text, text, date, text, uuid, smallint, text) from public, anon;
grant execute on function public.identity_add_to_season_roster(uuid, uuid, text, text, date, text, uuid, smallint, text) to authenticated;
