-- Lig başladıktan sonra kadroya ekleme yalnızca transfer döneminde açık.
-- Dönem dışında yalnız admin ve kurucu başkan ekleyebilir; takım sorumlusu
-- ekleme talebi açamaz, bölge sorumlusu ekleyemez ve ekleme talebini
-- onaylayamaz. Kadrodan çıkarma her zaman açık (onay akışı aynı).
--
-- Başladı = bugün (İstanbul) >= sezon başlangıç tarihi.
-- Transfer dönemi = turnuvada transfer açık ve bugün iki tarih arasında
-- (iki uç dahil); tarihlerden biri boşsa dönem yok sayılır.

create or replace function public.roster_add_open(p_season_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with today as (select (now() at time zone 'Europe/Istanbul')::date d)
  select coalesce((
    select s.start_date is null
        or (select d from today) < s.start_date
        or (l.transfer_enabled
            and s.transfer_start_date is not null
            and s.transfer_end_date is not null
            and (select d from today)
                between (s.transfer_start_date at time zone 'Europe/Istanbul')::date
                    and (s.transfer_end_date at time zone 'Europe/Istanbul')::date)
      from public.seasons s
      join public.leagues l on l.id = s.league_id
     where s.id = p_season_id
  ), true)
$$;

-- Bu kullanıcı şu an bu sezonda kadroya ekleyebilir mi (rol + dönem).
create or replace function public.roster_add_allowed(p_season_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.owns_season(p_season_id) or public.roster_add_open(p_season_id)
$$;

grant execute on function public.roster_add_allowed(uuid) to authenticated;
revoke all on function public.roster_add_open(uuid) from public, anon;
grant execute on function public.roster_add_open(uuid) to authenticated;

create or replace function public.guard_roster_add_window()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Yalnız uygulama kullanıcıları; cron / servis / SQL işlemleri serbest.
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_table_name = 'pending_actions' then
    if new.action_type <> 'roster_add' then
      return new;
    end if;
  elsif tg_op = 'UPDATE' then
    -- Pasif → aktif, takım ya da oyuncu değişimi ekleme sayılır.
    if not (new.is_active and (not coalesce(old.is_active, false)
                               or new.team_id is distinct from old.team_id
                               or new.player_id is distinct from old.player_id
                               or new.season_id is distinct from old.season_id)) then
      return new;
    end if;
  elsif not coalesce(new.is_active, true) then
    return new;
  end if;

  if not public.roster_add_allowed(new.season_id) then
    raise exception 'Lig başladığı için kadroya ekleme yalnızca transfer döneminde yapılabilir. Dönem dışında yalnızca admin ve kurucu başkan ekleyebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_roster_add_window on public.season_team_players;
create trigger guard_roster_add_window
  before insert or update on public.season_team_players
  for each row execute function public.guard_roster_add_window();

drop trigger if exists guard_roster_add_window on public.pending_actions;
create trigger guard_roster_add_window
  before insert on public.pending_actions
  for each row execute function public.guard_roster_add_window();
