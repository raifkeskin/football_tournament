-- Veri sürümleri: uygulama önbelleğinin geçersiz kılınması.
--
-- Her sezon için 'season:<id>', genel tablolar için '<tablo>' kapsamında bir
-- sayaç tutulur; ilgili satır eklenince / değişince / silinince sayaç artar.
-- Uygulama açılışta yalnızca bu küçük tabloyu okur; sayaç değişmediyse
-- telefondaki veriyi kullanır ve sorgu atmaz.
create table if not exists public.data_versions (
  scope text primary key,
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.data_versions enable row level security;
drop policy if exists data_versions_read on public.data_versions;
create policy data_versions_read on public.data_versions
  for select to anon, authenticated using (true);
revoke all on public.data_versions from anon, authenticated;
grant select on public.data_versions to anon, authenticated;

-- TG_ARGV[0]: 'season' (satırın season_id'si), 'self' (seasons: satırın id'si)
-- ya da boş (yalnız tablo kapsamı).
create or replace function public.bump_data_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scopes text[] := array[tg_table_name::text];
  v_kind text := coalesce(tg_argv[0], '');
begin
  if v_kind = 'season' then
    if tg_op <> 'INSERT' then
      if old.season_id is not null then
        v_scopes := v_scopes || ('season:' || old.season_id);
      end if;
    end if;
    if tg_op <> 'DELETE' then
      if new.season_id is not null then
        v_scopes := v_scopes || ('season:' || new.season_id);
      end if;
    end if;
  elsif v_kind = 'self' then
    if tg_op = 'DELETE' then
      v_scopes := v_scopes || ('season:' || old.id);
    else
      v_scopes := v_scopes || ('season:' || new.id);
    end if;
  end if;
  insert into public.data_versions (scope)
  select distinct s from unnest(v_scopes) s
  on conflict (scope) do update
    set version = public.data_versions.version + 1, updated_at = now();
  return null;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'groups', 'match_events', 'match_rosters', 'matches', 'news',
    'player_penalties', 'player_season_stats', 'season_regions',
    'season_registrations', 'season_team_players', 'season_teams',
    'team_managers'
  ] loop
    execute format('drop trigger if exists data_version on public.%I', t);
    execute format(
      'create trigger data_version after insert or update or delete on public.%I '
      'for each row execute function public.bump_data_version(%L)', t, 'season');
  end loop;
  foreach t in array array['teams', 'players', 'leagues', 'pitches'] loop
    execute format('drop trigger if exists data_version on public.%I', t);
    execute format(
      'create trigger data_version after insert or update or delete on public.%I '
      'for each row execute function public.bump_data_version()', t);
  end loop;
  drop trigger if exists data_version on public.seasons;
  create trigger data_version after insert or update or delete on public.seasons
    for each row execute function public.bump_data_version('self');
end $$;
