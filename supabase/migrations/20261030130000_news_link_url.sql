-- Elle yazılan haberde dış bağlantı (Instagram gönderisi vb.): haberde
-- "Instagram'da aç" / "Bağlantıyı aç" düğmesi.
alter table public.news add column if not exists link_url text;
alter table public.news drop constraint if exists news_link_url_http;
alter table public.news add constraint news_link_url_http
  check (link_url is null or link_url ~* '^https?://');
grant insert (link_url), update (link_url) on public.news to authenticated;
