-- Sorumlu bir yorumu silince ya da reddedince yazan kişiye bildirim gider
-- (anlık bildirim + uygulama içi). Kişi kendi yorumunu silerse gitmez.

create or replace function public.news_comment_removed_notice(
  p_user uuid, p_news uuid, p_body text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if p_user is null or p_user = auth.uid() then return; end if;
  perform public.push_send(
    array[p_user],
    'Yorumun kaldırıldı',
    '"' || left(p_body, 60) || case when length(p_body) > 60 then '…' else '' end
      || '" yorumun topluluk kurallarına uygun bulunmadığı için kaldırıldı. '
      || 'Saygılı ve yapıcı yorumlarınla tribünde yerin hep hazır.',
    '/',
    'news-' || p_news,
    true
  );
end;
$$;

revoke all on function public.news_comment_removed_notice(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function public.news_comment_delete(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  c record;
begin
  delete from public.news_comments nc
   using public.news n
   where nc.id = p_id and n.id = nc.news_id
     and (nc.user_id = auth.uid() or public.owns_news(n.season_id, n.region_id))
  returning nc.user_id, nc.news_id, nc.body, nc.status into c;
  if c.user_id is not null and c.status <> 'rejected' then
    perform public.news_comment_removed_notice(c.user_id, c.news_id, c.body);
  end if;
end;
$$;

create or replace function public.news_comment_review(p_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  c record;
begin
  select nc.id, nc.user_id, nc.news_id, nc.body, nc.status,
         n.season_id, n.region_id into c
    from public.news_comments nc join public.news n on n.id = nc.news_id
   where nc.id = p_id;
  if c.id is null then
    raise exception 'Yorum bulunamadı.';
  end if;
  if not public.owns_news(c.season_id, c.region_id) then
    raise exception 'Bu yorumu onaylama yetkiniz yok.';
  end if;
  if p_action not in ('publish', 'reject', 'ban') then
    raise exception 'Geçersiz işlem.';
  end if;
  update public.news_comments
     set status = case p_action when 'publish' then 'published'
                                else 'rejected' end,
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id;
  if p_action = 'ban' then
    insert into public.news_comment_bans (user_id, banned_by)
    values (c.user_id, auth.uid())
    on conflict (user_id) do nothing;
  end if;
  if p_action <> 'publish' and c.status <> 'rejected' then
    perform public.news_comment_removed_notice(c.user_id, c.news_id, c.body);
  end if;
end;
$$;
