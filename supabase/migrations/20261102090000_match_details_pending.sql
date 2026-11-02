-- Hızlı skorla bitirilen maçta "Maç detayları işleniyor..." ibaresi: olaylar
-- sonradan girilecek. Girilen goller skoru tutunca uygulama alanı kapatır;
-- o zamana kadar bitmiş maçta skor gollerden aşağı çekilmez.
alter table public.matches
  add column if not exists details_pending boolean not null default false;
