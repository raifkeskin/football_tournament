-- Bireysel sezon afişi + "Bu benim" yıldızı.
-- Futbolcu maç albümünde kendisinin olduğu fotoğrafı yıldızlar; sezon
-- afişini çıkarırken bu fotoğraflar arasından seçer. Yıldızı yalnız sahibi
-- ekler/kaldırır; admin, kurucu başkan ve bölge sorumlusu (başkası adına
-- afiş çıkarırken) okuyabilir.
-- Herkese açılana dek (player_poster_enabled) yalnız admin görür (UI).

create table if not exists public.player_photo_stars (
  player_id uuid not null references public.players(id) on delete cascade,
  media_id uuid not null references public.match_media(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (player_id, media_id)
);

create index if not exists player_photo_stars_media_idx
  on public.player_photo_stars (media_id);

alter table public.player_photo_stars enable row level security;

drop policy if exists player_photo_stars_select on public.player_photo_stars;
create policy player_photo_stars_select on public.player_photo_stars
  for select to authenticated
  using (
    player_id in (select p.id from public.players p
                  where p.auth_uid = auth.uid())
    or public.is_admin()
    or public.is_any_league_owner()
    or public.is_any_region_owner()
  );

drop policy if exists player_photo_stars_insert on public.player_photo_stars;
create policy player_photo_stars_insert on public.player_photo_stars
  for insert to authenticated
  with check (
    player_id in (select p.id from public.players p
                  where p.auth_uid = auth.uid())
  );

drop policy if exists player_photo_stars_delete on public.player_photo_stars;
create policy player_photo_stars_delete on public.player_photo_stars
  for delete to authenticated
  using (
    player_id in (select p.id from public.players p
                  where p.auth_uid = auth.uid())
  );

grant select, insert, delete on public.player_photo_stars to authenticated;

insert into public.app_settings (key, value)
values ('player_poster_enabled', 'false'::jsonb)
on conflict (key) do nothing;
