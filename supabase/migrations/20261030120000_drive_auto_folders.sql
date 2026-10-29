-- Drive'da maç klasörlerini otomatik açma: drive_folder_seasons'taki
-- sezonlar için LigMasasi / <Turnuva Yıl> / <N. Hafta> / <Ev - Dep | #LM…>
-- (drive-sync her turda eksikleri açar). Açılan klasör kaydedilir; Drive'da
-- silinen klasör yeniden açılmaz.

create table if not exists public.drive_folders (
  key text primary key,          -- season:<id> | week:<season>:<n> | match:<id>
  folder_id text not null,
  created_at timestamptz not null default now()
);
alter table public.drive_folders enable row level security;
revoke all on public.drive_folders from public, anon, authenticated;

insert into public.app_private_settings (key, value)
values ('drive_folder_seasons', '["cbad53c1-f295-497e-9f98-57f16a152679"]')
on conflict (key) do nothing;
