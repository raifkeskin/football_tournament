-- Turnuva talimatnamesi (statü): sezona bağlı serbest metin. "🏆" ile
-- başlayan satırlar uygulamada bölüm başlığı olur. Admin ve kurucu başkan
-- düzenler (seasons_update = owns_league); herkes okur. Yeni özellik:
-- regulations_enabled açılana kadar yalnız admin görür.

alter table public.seasons add column if not exists regulations text;
alter table public.seasons add column if not exists regulations_updated_at timestamptz;

create or replace function public.seasons_regulations_stamp()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.regulations is distinct from old.regulations then
    new.regulations_updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists seasons_regulations_stamp on public.seasons;
create trigger seasons_regulations_stamp
  before update of regulations on public.seasons
  for each row execute function public.seasons_regulations_stamp();

insert into public.app_settings (key, value)
values ('regulations_enabled', 'false'::jsonb)
on conflict (key) do nothing;
