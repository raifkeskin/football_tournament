-- Demo turnuvalar diğer turnuvalar gibi görünsün (2026-10-13 kararı).
-- can_view_league demo turnuvayı her zaman gizliyordu; liste kuralı
-- (leagues_read) ise yalnız is_private'a baktığından misafir demo turnuvayı
-- listede görüyor ama sezonları gizli kaldığından ana sayfada "Bu turnuvada
-- henüz sezon yok." çıkıyordu. Artık demo için ayrı akış yok: pasif değilse
-- ve gizli değilse herkes görür. is_demo yalnız demo_reset için kalır.

CREATE OR REPLACE FUNCTION public.can_view_league(p_league_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_raw text;
begin
  if p_league_id is null then
    return true;
  end if;
  -- Demo turnuva da diğerleri gibi: yalnız özellik açıksa ve gizliyse kısıtlı.
  if not public.private_leagues_enabled() then
    return true;
  end if;
  if not exists (
    select 1 from public.leagues where id = p_league_id and is_private
  ) then
    return true;
  end if;
  if v_uid is null then
    return false;
  end if;
  if public.owns_league(p_league_id)
     or public.is_region_owner_of_league(p_league_id) then
    return true;
  end if;

  -- Kodla takip (kod hâlâ geçerliyse).
  if exists (
    select 1 from public.league_followers f
    join public.leagues l on l.id = f.league_id
    where f.league_id = p_league_id and f.user_id = v_uid
      and lower(f.code) = lower(coalesce(l.access_code, ''))
  ) then
    return true;
  end if;

  -- Maç gözlemcisi.
  if exists (
    select 1 from public.matches m
    where m.league_id = p_league_id and m.observer_id = v_uid
  ) then
    return true;
  end if;

  -- Takım sorumlusu (sezon bazında ya da takımın sorumlusu).
  if exists (
    select 1 from public.team_managers tm
    join public.seasons s on s.id = tm.season_id
    where s.league_id = p_league_id and tm.user_id = v_uid
  ) or exists (
    select 1 from public.season_teams st
    join public.seasons s on s.id = st.season_id
    join public.teams t on t.id = st.team_id
    where s.league_id = p_league_id and t.manager_id = v_uid
  ) then
    return true;
  end if;

  -- Turnuvadaki bir takımın aktif oyuncusu (hesap e-postası <telefon>@...).
  v_raw := split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1);
  return exists (
    select 1 from public.season_team_players stp
    join public.seasons s on s.id = stp.season_id
    join public.players p on p.id = stp.player_id
    where s.league_id = p_league_id
      and coalesce(stp.is_active, true)
      and (p.auth_uid = v_uid
           or (v_raw <> '' and public.phone_raw10(p.phone) = v_raw))
  );
end;
$function$;
