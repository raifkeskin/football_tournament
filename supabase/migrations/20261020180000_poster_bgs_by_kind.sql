-- Afiş türüne göre arka plan: maç, haftalık fikstür, maç sonuçları ve puan
-- durumu afişleri ayrı görsel kullanabilir. `poster_bg_url` ortak görsel
-- olarak kalır; türün görseli yoksa o kullanılır. Kadro, esame ve diziliş
-- afişleri takım rengiyle çizilir, arka plan almaz.
--   poster_bgs = {"match": url, "fixture": url, "results": url, "standings": url}
-- Admin ve turnuvanın kurucu başkanı değiştirebilir.

alter table public.leagues
  add column if not exists poster_bgs jsonb not null default '{}'::jsonb;

create or replace function public.guard_league_poster_bg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.poster_bg_url is distinct from old.poster_bg_url
      or new.poster_bgs is distinct from old.poster_bgs)
     and coalesce(auth.role(), '') in ('authenticated', 'anon')
     and not (public.is_admin() or public.owns_league(new.id)) then
    raise exception 'Afiş arka planını yalnızca admin ve kurucu başkan değiştirebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_league_poster_bg on public.leagues;
create trigger guard_league_poster_bg
  before update of poster_bg_url, poster_bgs on public.leagues
  for each row execute function public.guard_league_poster_bg();

-- posters/ klasörüne admin ve kurucu başkanlar yükler.
create or replace function public.can_upload_media(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (p_folder = 'posters' and (public.is_admin() or public.is_any_league_owner()))
    or (
      p_folder in ('leagues', 'teams', 'players', 'news', 'matches', 'sponsors')
      and (
        public.is_admin()
        or public.is_any_league_owner()
        or (
          p_folder = 'players'
          and exists (select 1 from public.team_managers where user_id = auth.uid())
        )
      )
    )
$$;
