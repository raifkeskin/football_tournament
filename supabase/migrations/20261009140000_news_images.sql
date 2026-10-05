-- Haberlerde birden fazla fotoğraf (en fazla 5). image_url kapak olarak
-- kalır (ilk fotoğraf) ve image_urls ile otomatik eşitlenir; yalnız
-- image_url yazan eski uygulama sürümleri de çalışmaya devam eder.

alter table public.news
  add column if not exists image_urls text[] not null default '{}'
    check (cardinality(image_urls) <= 5);

update public.news
   set image_urls = array[image_url]
 where image_url is not null and image_url <> ''
   and cardinality(image_urls) = 0;

create or replace function public.news_sync_cover()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' then
    if cardinality(new.image_urls) > 0 then
      new.image_url := new.image_urls[1];
    elsif coalesce(new.image_url, '') <> '' then
      new.image_urls := array[new.image_url];
    end if;
  elsif new.image_urls is distinct from old.image_urls then
    new.image_url := new.image_urls[1];
  elsif new.image_url is distinct from old.image_url then
    new.image_urls := case when coalesce(new.image_url, '') = '' then '{}'
                           else array[new.image_url] end;
  end if;
  return new;
end;
$$;

drop trigger if exists news_sync_cover on public.news;
create trigger news_sync_cover
  before insert or update on public.news
  for each row execute function public.news_sync_cover();

-- news tablosunda sütun bazlı yetki var: yeni sütun da yazılabilsin.
grant insert (image_urls), update (image_urls) on public.news to authenticated;
