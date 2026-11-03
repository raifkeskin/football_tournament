-- Takip Listem: yıldızla takım ve futbolcu takibi (turnuva takibi
-- followed_leagues'te kalır). Turnuva başına tek takım kuralı (followed_teams)
-- yeni listede yok; eski derlemeler followed_teams'e yazmaya devam eder, ikisi
-- birlikte okunur. Yeni özellik: follow_list_enabled kapalı (admin görür).

create table if not exists public.user_follows (
  user_id    uuid not null references auth.users (id) on delete cascade,
  kind       text not null check (kind in ('team', 'player')),
  target_id  uuid not null,
  league_id  uuid references public.leagues (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, kind, target_id)
);
create index if not exists user_follows_target_idx
  on public.user_follows (kind, target_id);
alter table public.user_follows enable row level security;
drop policy if exists user_follows_own on public.user_follows;
create policy user_follows_own on public.user_follows for all
  to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Mevcut takipler yeni listeye de (silinmez).
insert into public.user_follows (user_id, kind, target_id, league_id, created_at)
select f.user_id, 'team', f.team_id, f.league_id, f.created_at
from public.followed_teams f
on conflict do nothing;

-- Bildirim kitlesi: yeni listedeki takımlar da "Takip ettiğim takımlar".
create or replace function public.match_audience(p_match_id uuid, p_include_followers boolean)
 returns uuid[]
 language sql
 stable security definer
 set search_path to ''
as $function$
  with m as (
    select mt.season_id, mt.league_id, mt.group_id,
           mt.home_team_id, mt.away_team_id, g.region_id
    from public.matches mt
    left join public.groups g on g.id = mt.group_id
    where mt.id = p_match_id
  ),
  -- Sezondaki oyuncular ve takım sorumluları, takımlarının grubuyla.
  members as (
    select p.auth_uid as uid, stp.team_id
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    join m on stp.season_id = m.season_id
    where stp.is_active
    union
    select tm.user_id, tm.team_id
    from public.team_managers tm
    join m on tm.season_id = m.season_id
  ),
  member_groups as (
    select mb.uid, mb.team_id, st.group_id
    from members mb
    join m on true
    left join public.season_teams st
      on st.season_id = m.season_id and st.team_id = mb.team_id
  ),
  ids as (
    -- Takımımın maçları
    select mg.uid from member_groups mg
    join m on mg.team_id in (m.home_team_id, m.away_team_id)
    left join public.notification_prefs np on np.user_id = mg.uid
    where coalesce(np.scope_my_team, true)
    union
    -- Grubumdaki tüm maçlar
    select mg.uid from member_groups mg
    join m on mg.group_id = m.group_id
    join public.notification_prefs np on np.user_id = mg.uid
    where np.scope_group
    union
    -- Turnuvanın tüm maçları
    select mg.uid from member_groups mg
    join public.notification_prefs np on np.user_id = mg.uid
    where np.scope_league
    union
    -- Takip ettiğim takımlar (eski tek takım + Takip Listem)
    select f.user_id from public.followed_teams f
    join m on f.team_id in (m.home_team_id, m.away_team_id)
    left join public.notification_prefs np on np.user_id = f.user_id
    where coalesce(np.scope_followed, true)
    union
    select uf.user_id from public.user_follows uf
    join m on uf.kind = 'team'
      and uf.target_id in (m.home_team_id, m.away_team_id)
    left join public.notification_prefs np on np.user_id = uf.user_id
    where coalesce(np.scope_followed, true)
    union
    -- Takip ettiğim turnuvalar (misafir dahil)
    select fl.user_id from public.followed_leagues fl
    join m on fl.league_id = m.league_id
    union
    -- Yöneticiler
    select o.user_id from public.league_owners o
    join m on o.league_id = m.league_id
    union
    select ro.user_id from m
    join public.region_owners ro on ro.region_id = m.region_id
    union
    -- Kodla takip edenler (yalnız sonuç)
    select f.user_id from public.league_followers f
    join m on f.league_id = m.league_id
    where p_include_followers
  )
  select coalesce(array_agg(distinct uid), '{}') from ids where uid is not null
$function$;

insert into public.app_settings (key, value)
values ('follow_list_enabled', 'false'::jsonb)
on conflict (key) do nothing;
