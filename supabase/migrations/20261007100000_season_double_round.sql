-- Sezonun lig aşaması tek maç mı (false) rövanşlı mı (true)?
-- Fikstür kurası bu ayara göre eşleşme üretir.
alter table public.seasons
  add column if not exists is_double_round boolean not null default false;
