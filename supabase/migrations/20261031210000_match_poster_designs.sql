-- Takım odaklı maç afişleri: takımın forma deseni (Çizgili / Düz / Parçalı)
-- ve yeni tasarımları herkese açan anahtar (kapalıyken yalnız admin).

alter table public.teams
  add column if not exists jersey_style text
  check (jersey_style in ('stripes', 'plain', 'half'));

insert into public.app_settings (key, value)
values ('match_poster_designs_enabled', 'false'::jsonb)
on conflict (key) do nothing;
