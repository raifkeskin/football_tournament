-- Uygulama geneli ayarlar (herkes okur, yalnızca admin yazar).
--
-- private_leagues_enabled: gizli turnuva özelliği. Kapalıyken (varsayılan)
-- turnuvaların is_private işareti yok sayılır ve tüm turnuvalar herkese
-- görünür; uygulamada "Turnuva Kodu Gir" ve "Gizli turnuva" alanları gizlenir.
-- Turnuvaların is_private / access_code değerleri silinmez; özellik
-- açılınca eski hâline döner.

create table if not exists public.app_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;

drop policy if exists app_settings_read on public.app_settings;
create policy app_settings_read on public.app_settings for select
  using (true);

drop policy if exists app_settings_admin_write on public.app_settings;
create policy app_settings_admin_write on public.app_settings for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select on public.app_settings to anon, authenticated;
grant insert, update, delete on public.app_settings to authenticated;

insert into public.app_settings (key, value)
values ('private_leagues_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.private_leagues_enabled()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(
    (select value = 'true'::jsonb from public.app_settings
     where key = 'private_leagues_enabled'),
    false
  )
$$;

grant execute on function public.private_leagues_enabled() to anon, authenticated;

-- Özellik kapalıyken her turnuva görülebilir.
create or replace function public.can_view_league(p_league_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_raw text;
begin
  if p_league_id is null then
    return true;
  end if;
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
  if public.owns_league(p_league_id) then
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
$$;
