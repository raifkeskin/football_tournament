-- Turnuvanın afiş arka planı: maç, fikstür, kadro, diziliş ve puan durumu
-- afişlerinde zemin olarak kullanılan tek görsel. Boşsa afişler kendi
-- varsayılan zeminleriyle çizilir. Şimdilik yalnızca admin ekler/değiştirir.
-- Görsel media/posters/ altında durur; yenisi yüklenince eskisi uygulama
-- tarafından silinir (turnuva başına tek dosya).

alter table public.leagues
  add column if not exists poster_bg_url text;

-- Kurucu başkanlar turnuvayı düzenleyebilir ama afiş zeminini değiştiremez.
create or replace function public.guard_league_poster_bg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.poster_bg_url is distinct from old.poster_bg_url
     and coalesce(auth.role(), '') in ('authenticated', 'anon')
     and not public.is_admin() then
    raise exception 'Afiş arka planını yalnızca admin değiştirebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_league_poster_bg on public.leagues;
create trigger guard_league_poster_bg
  before update of poster_bg_url on public.leagues
  for each row execute function public.guard_league_poster_bg();

-- posters/ klasörüne yalnızca admin yükler.
create or replace function public.can_upload_media(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (p_folder = 'posters' and public.is_admin())
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
