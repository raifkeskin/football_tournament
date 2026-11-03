-- Dizilişte dekupe (arka planı silinmiş) oyuncu fotoğrafı. Dekupe asıl
-- fotoğrafın adresine bağlıdır: fotoğraf değişince ya da izin yüzünden
-- gizlenince (players.photo_url boşalır) eşleşme kalmaz, daire görünür.
create table if not exists public.player_photo_cutouts (
  photo_url text primary key,
  cutout_url text not null,
  created_at timestamptz not null default now()
);
alter table public.player_photo_cutouts enable row level security;

drop policy if exists player_photo_cutouts_read on public.player_photo_cutouts;
create policy player_photo_cutouts_read on public.player_photo_cutouts
  for select using (true);

drop policy if exists player_photo_cutouts_admin on public.player_photo_cutouts;
create policy player_photo_cutouts_admin on public.player_photo_cutouts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.player_photo_cutouts to anon, authenticated;
grant insert, update, delete on public.player_photo_cutouts to authenticated;

-- Yeni özellik: yalnız admin görür, açılınca herkese.
insert into public.app_settings (key, value)
values ('lineup_cutouts_enabled', 'false'::jsonb)
on conflict (key) do nothing;
