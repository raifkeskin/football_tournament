-- Aynı kişinin iki kez kaydedilmesini önler: ad + soyad + doğum tarihi
-- benzersiz (telefondan bağımsız). Telefon benzersizliği ayrı kuraldır
-- (players_phone_uq). Karşılaştırma büyük/küçük harf, Türkçe İ/I ve fazla
-- boşluktan etkilenmez.
create or replace function public.norm_person_name(p text)
returns text
language sql
immutable
parallel safe
set search_path to ''
as $$
  select regexp_replace(
    lower(translate(trim(coalesce(p, '')), 'İIı', 'iii')),
    '\s+', ' ', 'g')
$$;

create unique index if not exists players_identity_uq
  on public.players (
    public.norm_person_name(name),
    public.norm_person_name(surname),
    birth_date
  );
