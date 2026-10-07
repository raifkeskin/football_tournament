-- Turnuva sponsorları: ana sponsorlar ve alt sponsorlar. Ana sayfadaki
-- şeritte sırayla döner (önce ana, sonra alt); ekranda kalma süreleri
-- turnuva ayarında. Yalnızca admin ve turnuvanın kurucu başkanları yönetir.

-- Eski, boş ve kullanılmayan sponsors tablosu (id, name, photo_url) genişletilir.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'sponsors'
               and column_name = 'photo_url') then
    alter table public.sponsors rename column photo_url to logo_url;
  end if;
end $$;

alter table public.sponsors
  add column if not exists league_id uuid not null references public.leagues(id) on delete cascade,
  add column if not exists tier text not null default 'main' check (tier in ('main', 'sub')),
  add column if not exists link_url text,
  add column if not exists sort_order integer not null default 0,
  add column if not exists is_active boolean not null default true;

update public.sponsors set logo_url = '' where logo_url is null;
alter table public.sponsors
  alter column logo_url set default '',
  alter column logo_url set not null,
  alter column created_at set not null,
  alter column created_at set default now(),
  alter column updated_at set not null,
  alter column updated_at set default now();

drop policy if exists sponsors_write on public.sponsors;

create index if not exists sponsors_league_idx
  on public.sponsors (league_id, tier, sort_order);

drop trigger if exists set_updated_at on public.sponsors;
create trigger set_updated_at before update on public.sponsors
  for each row execute function public.set_updated_at();

alter table public.sponsors enable row level security;

drop policy if exists sponsors_read on public.sponsors;
create policy sponsors_read on public.sponsors for select
  using (public.can_view_league(league_id));

drop policy if exists sponsors_insert on public.sponsors;
create policy sponsors_insert on public.sponsors for insert to authenticated
  with check (public.owns_league(league_id));

drop policy if exists sponsors_update on public.sponsors;
create policy sponsors_update on public.sponsors for update to authenticated
  using (public.owns_league(league_id)) with check (public.owns_league(league_id));

drop policy if exists sponsors_delete on public.sponsors;
create policy sponsors_delete on public.sponsors for delete to authenticated
  using (public.owns_league(league_id));

-- Şeritte ekranda kalma süreleri (saniye).
alter table public.leagues
  add column if not exists sponsor_main_seconds integer not null default 8
    check (sponsor_main_seconds between 2 and 60),
  add column if not exists sponsor_sub_seconds integer not null default 4
    check (sponsor_sub_seconds between 2 and 60);

-- Sponsor logoları media/sponsors/ altına (admin ve kurucu başkanlar).
create or replace function public.can_upload_media(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_folder in ('leagues', 'teams', 'players', 'news', 'matches', 'sponsors')
    and (
      public.is_admin()
      or public.is_any_league_owner()
      or (
        p_folder = 'players'
        and exists (select 1 from public.team_managers where user_id = auth.uid())
      )
    )
$$;
