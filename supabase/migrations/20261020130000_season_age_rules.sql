-- Sezon yaş ve kontenjan kuralları (40+, 47+ turnuvaları).
-- seasons.age_rules (jsonb):
--   player_max_year : oyuncular için en geç doğum yılı (ör. 1986)
--   gk_max_year     : kaleci için en geç doğum yılı (ör. 1991)
--   quotas          : [{years:[1988,1989], max:3, field_max:2, gk:false}]
--                     gk=true kontenjan yalnız kalecilere uygulanır.
-- Yalnız admin ve turnuvanın kurucu başkanı değiştirir. Bu aşamada kurallar
-- yalnız gösterilir; kadroya eklemede engel sonraki aşamada.

alter table public.seasons add column if not exists age_rules jsonb;

create or replace function public.guard_season_age_rules()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon')
     and new.age_rules is distinct from old.age_rules
     and not public.owns_league(new.league_id) then
    raise exception 'Yaş ve kontenjan kurallarını yalnızca admin ve kurucu başkan değiştirebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_season_age_rules on public.seasons;
create trigger guard_season_age_rules
  before update of age_rules on public.seasons
  for each row execute function public.guard_season_age_rules();
