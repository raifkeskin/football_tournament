-- Haber manşeti: otomatik haberin kurallarla yazılan başlığı yerine turnuva
-- / bölge sorumlusunun düzenlediği manşet (boş = otomatik).
alter table public.news add column if not exists headline text;
alter table public.news drop constraint if exists news_headline_len;
alter table public.news add constraint news_headline_len
  check (headline is null or char_length(headline) between 1 and 140);
grant update (headline) on public.news to authenticated;
