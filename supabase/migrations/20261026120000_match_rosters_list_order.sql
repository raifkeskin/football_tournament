-- Esamedeki oyuncu sırası (kağıttaki / esame ekranındaki sıra). Kadro sekmesi
-- bu sırayla gösterir; eski sürümlerin kayıtlarında boş kalır.
alter table public.match_rosters add column if not exists list_order smallint;
