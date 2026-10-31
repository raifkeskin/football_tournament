-- Kullanıcının kendi engellemesi (Apple 1.2): engellediği kişinin yorumlarını
-- görmez; engelleme yorumu ayrıca şikâyet sayılır. Yorum kuralları onayı:
-- ilk yorumdan önce bir kez.

create table if not exists public.news_comment_blocks (
  user_id uuid not null references auth.users(id) on delete cascade,
  blocked_user_id uuid not null references auth.users(id) on delete cascade,
  blocked_name text not null default '',
  created_at timestamptz not null default now(),
  primary key (user_id, blocked_user_id)
);
alter table public.news_comment_blocks enable row level security;

drop policy if exists news_comment_blocks_read on public.news_comment_blocks;
create policy news_comment_blocks_read on public.news_comment_blocks
  for select to authenticated using (user_id = auth.uid());

create table if not exists public.news_comment_terms (
  user_id uuid primary key references auth.users(id) on delete cascade,
  accepted_at timestamptz not null default now()
);
alter table public.news_comment_terms enable row level security;

drop policy if exists news_comment_terms_read on public.news_comment_terms;
create policy news_comment_terms_read on public.news_comment_terms
  for select to authenticated using (user_id = auth.uid());

-- Yorumun yazarını engeller (ve yorumu şikâyet eder).
create or replace function public.news_comment_block(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  c record;
begin
  if v_uid is null then
    raise exception 'Engellemek için giriş yapın.';
  end if;
  select user_id, author_name into c
    from public.news_comments where id = p_comment_id;
  if c.user_id is null then
    raise exception 'Yorum bulunamadı.';
  end if;
  if c.user_id = v_uid then
    raise exception 'Kendini engelleyemezsin.';
  end if;
  insert into public.news_comment_blocks (user_id, blocked_user_id, blocked_name)
  values (v_uid, c.user_id, coalesce(c.author_name, ''))
  on conflict (user_id, blocked_user_id) do nothing;
  perform public.news_comment_report(p_comment_id);
end;
$$;

create or replace function public.news_comment_unblock(p_user_id uuid)
returns void
language sql
security definer
set search_path to ''
as $$
  delete from public.news_comment_blocks
   where user_id = auth.uid() and blocked_user_id = p_user_id
$$;

create or replace function public.news_comment_accept_terms()
returns void
language sql
security definer
set search_path to ''
as $$
  insert into public.news_comment_terms (user_id)
  select auth.uid() where auth.uid() is not null
  on conflict (user_id) do nothing
$$;

revoke all on function public.news_comment_block(uuid) from public, anon;
revoke all on function public.news_comment_unblock(uuid) from public, anon;
revoke all on function public.news_comment_accept_terms() from public, anon;
grant execute on function public.news_comment_block(uuid) to authenticated;
grant execute on function public.news_comment_unblock(uuid) to authenticated;
grant execute on function public.news_comment_accept_terms() to authenticated;
grant select on public.news_comment_blocks, public.news_comment_terms to authenticated;
