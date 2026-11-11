-- Sezon bazlı mavi tik: kadroya eklemede kimlik kuralı (Kapalı / Uyar / Engelle).
-- Esame kuralı zaten verified_id_mode ile sunucuda zorlanıyor (match_rosters tetikleyicisi).
alter table public.seasons
  add column if not exists verified_id_roster text not null default 'off'
  check (verified_id_roster in ('off', 'warn', 'block'));

-- Oyuncunun kimliği bu sezonun istediği düzeyde mi (mode any ise hep evet).
create or replace function public.identity_ok_for_season(p_player uuid, p_season uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(s.verified_id_mode, 'any') = 'any'
      or exists (select 1 from public.player_verifications v
                  where v.player_id = p_player
                    and (s.verified_id_mode = 'chip_ibraz' or v.method <> 'ibraz'))
    from public.seasons s where s.id = p_season
$$;

-- İstemci ön kontrolü: ok | warn | block.
create or replace function public.identity_roster_check(p_season uuid, p_player uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when s.verified_id_mode = 'any' or s.verified_id_roster = 'off' then 'ok'
    when public.identity_ok_for_season(p_player, p_season) then 'ok'
    else s.verified_id_roster end
  from public.seasons s where s.id = p_season
$$;

-- Engelle modunda mavi tiksiz oyuncu kadroya eklenemez (admin hariç).
create or replace function public.season_team_players_require_verified()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_name text;
begin
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  if not coalesce(new.is_active, true) then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.is_active is not distinct from new.is_active
     and old.team_id is not distinct from new.team_id
     and old.player_id is not distinct from new.player_id then
    return new;
  end if;
  if public.identity_roster_check(new.season_id, new.player_id) = 'block' then
    select p.name || ' ' || p.surname into v_name from public.players p where p.id = new.player_id;
    raise exception 'KIMLIK_ONAYSIZ: % kimliği onaylı değil; bu sezonda kadroya eklenemez.',
      coalesce(v_name, 'Oyuncu');
  end if;
  return new;
end $$;

drop trigger if exists season_team_players_require_verified on public.season_team_players;
create trigger season_team_players_require_verified
  before insert or update on public.season_team_players
  for each row execute function public.season_team_players_require_verified();

-- Ana sayfa uyarıları: kendi kadro satırlarım (oyuncu) ve yönettiğim takımların mavi tiksiz oyuncuları.
create or replace function public.my_identity_warnings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare me jsonb; mgr jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('player', '[]'::jsonb, 'teams', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'season_id', s.id, 'league', l.name, 'mode', s.verified_id_mode, 'roster', s.verified_id_roster)), '[]'::jsonb)
    into me
    from public.players p
    join public.season_team_players stp on stp.player_id = p.id and stp.is_active
    join public.seasons s on s.id = stp.season_id and s.deleted_at is null and s.verified_id_mode <> 'any'
    join public.leagues l on l.id = s.league_id
   where p.auth_uid = auth.uid()
     and not public.identity_ok_for_season(p.id, s.id);
  select coalesce(jsonb_agg(x), '[]'::jsonb) into mgr from (
    select jsonb_build_object(
             'season_id', s.id, 'team_id', t.id, 'team', t.name, 'league', l.name,
             'players', jsonb_agg(trim(p.name || ' ' || p.surname) order by p.name)) as x
      from public.season_teams st
      join public.seasons s on s.id = st.season_id and s.deleted_at is null and s.verified_id_mode <> 'any'
      join public.leagues l on l.id = s.league_id
      join public.teams t on t.id = st.team_id
      join public.season_team_players stp on stp.season_id = s.id and stp.team_id = t.id and stp.is_active
      join public.players p on p.id = stp.player_id
     where (public.manages_team(s.id, t.id) or public.attendance_is_manager(s.id, t.id))
       and not public.identity_ok_for_season(p.id, s.id)
     group by s.id, t.id, t.name, l.name
  ) q;
  return jsonb_build_object('player', me, 'teams', mgr);
end $$;

revoke all on function public.identity_ok_for_season(uuid, uuid) from public, anon;
revoke all on function public.identity_roster_check(uuid, uuid) from public, anon;
revoke all on function public.my_identity_warnings() from public, anon;
grant execute on function public.identity_ok_for_season(uuid, uuid) to authenticated;
grant execute on function public.identity_roster_check(uuid, uuid) to authenticated;
grant execute on function public.my_identity_warnings() to authenticated;
