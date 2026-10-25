-- Pasif turnuvalar her yerde gizli (25.10.2026): can_view_league pasif
-- turnuvaya false döner; matches, match_events, match_rosters, seasons,
-- groups, season_team_players, news, match_media, match_highlights,
-- sponsors okuma kuralları bu fonksiyondan geçer.
CREATE OR REPLACE FUNCTION public.can_view_league(p_league_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_raw text;
  v_private boolean;
  v_passive boolean;
begin
  if p_league_id is null then
    return true;
  end if;
  select l.is_private,
         coalesce(l.status, '') = 'passive' or l.is_active is false
    into v_private, v_passive
    from public.leagues l where l.id = p_league_id;
  -- Pasif turnuvanın verisi (sezon, maç, olay, kadro, haber, medya,
  -- sponsor) kimseye gelmez; admin dahil. Turnuva satırı Turnuva
  -- Yönetimi'nde görünür, aktife alınınca her şey geri gelir.
  if coalesce(v_passive, false) then
    return false;
  end if;
  -- Demo turnuva da diğerleri gibi: yalnız özellik açıksa ve gizliyse kısıtlı.
  if not public.private_leagues_enabled() then
    return true;
  end if;
  if not coalesce(v_private, false) then
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

-- Turnuva satırı: sahibi ve admin pasif (gizli) turnuvayı da görür ki
-- Turnuva Yönetimi'nden yeniden aktife alınabilsin.
drop policy if exists leagues_read on public.leagues;
create policy leagues_read on public.leagues for select
  using ((not is_private) or public.can_view_league(id) or public.owns_league(id));
