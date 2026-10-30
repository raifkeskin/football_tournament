-- Haber metni: kurallarla yazılan metin yerine sorumlunun düzenlediği metin
-- (boş = otomatik). Otomatik haber yenilense de korunur.
alter table public.news add column if not exists article text;
alter table public.news drop constraint if exists news_article_len;
alter table public.news add constraint news_article_len
  check (article is null or char_length(article) between 1 and 4000);
grant update (article) on public.news to authenticated;
