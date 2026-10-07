-- Oyuncu rolü (Futbolcu / Takım Sorumlusu / Her İkisi) kaldırıldı: players
-- tablosundaki herkes futbolcudur; takım sorumlusu yalnızca Takım
-- Yönetimi'nden seçilir (teams.manager_id → team_managers, bkz.
-- 20261010100000_team_manager_sync.sql).

drop view if exists public.players_public;
create view public.players_public
with (security_invoker = false) as
select
  p.id,
  p.name,
  p.surname,
  p.photo_url,
  p.main_position,
  p.sub_position,
  p.preferred_foot,
  p.height,
  p.weight,
  extract(year from p.birth_date)::int as birth_year,
  (public.phone_raw10(p.phone) is null) as pending_match,
  p.created_at,
  p.updated_at
from public.players p;

revoke all on public.players_public from public;
grant select on public.players_public to anon, authenticated;

alter table public.players drop column if exists role;
