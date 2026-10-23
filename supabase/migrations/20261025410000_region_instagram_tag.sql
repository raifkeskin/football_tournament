-- Bölge başına Instagram etiketi: turnuvanın tek Instagram hesabı varken
-- gönderi açıklamasında bölgenin etiketi (#anadolu gibi) geçiyorsa gönderi
-- hemen yayınlanır ve o bölgenin haberi olur (instagram-sync).
-- Etiket # olmadan saklanır; harf, rakam ve alt çizgi.

alter table public.season_regions
  add column if not exists instagram_tag text;

alter table public.season_regions
  drop constraint if exists season_regions_instagram_tag_check;
alter table public.season_regions
  add constraint season_regions_instagram_tag_check
  check (instagram_tag is null or instagram_tag ~ '^[[:alnum:]_]{2,40}$');
