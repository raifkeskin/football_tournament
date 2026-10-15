-- Sponsor şeridinde adın yazı stili: sade (A), kurumsal (B), spor (C).
-- Yalnız ekleme: eski sürümler kolonu okumaz; yeni kayıtlar varsayılan alır.
alter table public.sponsors
  add column if not exists name_style text not null default 'sade'
  check (name_style in ('sade', 'kurumsal', 'spor'));
