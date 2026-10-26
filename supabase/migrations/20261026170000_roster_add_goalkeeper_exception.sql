-- Kaleci istisnası (sezon ayarı, varsayılan kapalı): açıksa lig başladıktan
-- sonra transfer dönemi dışında da ana mevkisi "Kaleci" olan oyuncu kadroya
-- eklenebilir / eklenmesi talep edilebilir. Diğer mevkiler kurala bağlı.

alter table public.seasons
  add column if not exists goalkeeper_add_anytime boolean not null default false;

-- Bu oyuncu bu sezonda şu an eklenebilir mi (rol + dönem + kaleci istisnası).
create or replace function public.roster_add_allowed(
  p_season_id uuid,
  p_player_id uuid,
  p_new_position text default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.owns_season(p_season_id)
      or public.roster_add_open(p_season_id)
      or (coalesce((select s.goalkeeper_add_anytime from public.seasons s
                     where s.id = p_season_id), false)
          and coalesce(
                (select p.main_position from public.players p
                  where p.id = p_player_id),
                p_new_position, '') = 'Kaleci')
$$;

-- Ekranın ön kontrolü: bu sezonda herhangi bir ekleme yapılabilir mi
-- (kaleci istisnası açıksa seçici açılır, kaleci olmayan sunucuda reddedilir).
create or replace function public.roster_add_allowed(p_season_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.owns_season(p_season_id)
      or public.roster_add_open(p_season_id)
      or coalesce((select s.goalkeeper_add_anytime from public.seasons s
                    where s.id = p_season_id), false)
$$;

revoke all on function public.roster_add_allowed(uuid, uuid, text) from public, anon;
grant execute on function public.roster_add_allowed(uuid, uuid, text) to authenticated;

create or replace function public.guard_roster_add_window()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player uuid;
  v_new_position text;
  v_gk boolean;
begin
  -- Yalnız uygulama kullanıcıları; cron / servis / SQL işlemleri serbest.
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_table_name = 'pending_actions' then
    if new.action_type <> 'roster_add' then
      return new;
    end if;
    v_player := nullif(new.payload ->> 'player_id', '')::uuid;
    v_new_position := nullif(trim(new.payload -> 'player' ->> 'main_position'), '');
  elsif tg_op = 'UPDATE' then
    -- Pasif → aktif, takım ya da oyuncu değişimi ekleme sayılır.
    if not (new.is_active and (not coalesce(old.is_active, false)
                               or new.team_id is distinct from old.team_id
                               or new.player_id is distinct from old.player_id
                               or new.season_id is distinct from old.season_id)) then
      return new;
    end if;
    v_player := new.player_id;
  elsif not coalesce(new.is_active, true) then
    return new;
  else
    v_player := new.player_id;
  end if;

  if not public.roster_add_allowed(new.season_id, v_player, v_new_position) then
    select coalesce(s.goalkeeper_add_anytime, false) into v_gk
      from public.seasons s where s.id = new.season_id;
    raise exception '%',
      'Lig başladığı için kadroya ekleme yalnızca transfer döneminde yapılabilir.'
      || case when v_gk then ' Bu dönemde yalnızca kaleci eklenebilir.' else '' end
      || ' Dönem dışında yalnızca admin ve kurucu başkan ekleyebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
