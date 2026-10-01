-- ============================================================================
-- Haberler akışı (v1): tek fotoğraf + giriş yapmış kullanıcı beğenisi
--
-- C1  news.image_url, news.like_count
-- C2  news_likes        : kullanıcı başına bir beğeni
-- C3  like_count        : beğeni eklenince/silinince sunucuda güncellenir
-- C4  news.updated_at   : sadece içerik değişince güncellenir (beğeni değil)
-- C5  sütun yetkileri   : like_count istemciden yazılamaz
--
-- psql --single-transaction ile çalıştırılır; bir adım hata verirse hiçbiri
-- uygulanmaz.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- C1) news: fotoğraf ve beğeni sayısı
-- ----------------------------------------------------------------------------
alter table public.news add column if not exists image_url text;
alter table public.news
  add column if not exists like_count integer not null default 0;

create index if not exists news_published_created_idx
  on public.news (created_at desc) where is_published;

-- ----------------------------------------------------------------------------
-- C2) news_likes
-- ----------------------------------------------------------------------------
create table if not exists public.news_likes (
  news_id    uuid not null references public.news (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (news_id, user_id)
);
create index if not exists news_likes_user_idx on public.news_likes (user_id);

alter table public.news_likes enable row level security;
drop policy if exists news_likes_read on public.news_likes;
drop policy if exists news_likes_insert on public.news_likes;
drop policy if exists news_likes_delete on public.news_likes;
-- Herkes sadece kendi beğenilerini görür (toplam sayı news.like_count'ta).
create policy news_likes_read on public.news_likes for select to authenticated
  using (user_id = auth.uid());
create policy news_likes_insert on public.news_likes for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.news n where n.id = news_id and n.is_published
    )
  );
create policy news_likes_delete on public.news_likes for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, delete on public.news_likes to authenticated;

drop trigger if exists set_updated_at on public.news_likes;
create trigger set_updated_at before update on public.news_likes
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- C3) like_count'u sunucuda tut
-- ----------------------------------------------------------------------------
create or replace function public.news_likes_sync_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.news set like_count = like_count + 1 where id = new.news_id;
  elsif tg_op = 'DELETE' then
    update public.news set like_count = greatest(like_count - 1, 0)
    where id = old.news_id;
  end if;
  return null;
end;
$$;

drop trigger if exists news_likes_sync_count on public.news_likes;
create trigger news_likes_sync_count
  after insert or delete on public.news_likes
  for each row execute function public.news_likes_sync_count();

-- ----------------------------------------------------------------------------
-- C4) news.updated_at sadece içerik değişince
-- ----------------------------------------------------------------------------
drop trigger if exists set_updated_at on public.news;
create trigger set_updated_at
  before update of league_id, content, is_published, image_url on public.news
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- C5) like_count istemciden yazılamaz (RLS satırı korur, bu sütunu korur)
-- ----------------------------------------------------------------------------
revoke insert, update on public.news from anon, authenticated;
grant insert (league_id, content, is_published, image_url)
  on public.news to authenticated;
grant update (league_id, content, is_published, image_url)
  on public.news to authenticated;
