-- Haberler sezona bağlanınca (20261017120000) yeni season_id sütununa ekleme
-- izni verilmemişti: uygulamadan elle haber eklemek herkes için
-- "permission denied for table news" hatası veriyordu. Yetki yine
-- news_write kuralıyla (owns_news) sınırlı.
grant insert (season_id) on public.news to authenticated;
