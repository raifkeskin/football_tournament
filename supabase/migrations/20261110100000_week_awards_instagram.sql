-- Haftanın Enleri bülteni: yayınlandıktan sonra tek değiştirilebilen şey
-- Instagram gönderisi / Reels bağlantısı (bültenin son sayfası olarak gösterilir).
create or replace function public.set_week_awards_instagram(p_news_id uuid, p_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  n record;
  v_url text := nullif(trim(coalesce(p_url, '')), '');
begin
  select id, season_id, region_id into n
    from public.news where id = p_news_id and auto_kind = 'week_awards';
  if not found then
    raise exception 'Bülten bulunamadı.';
  end if;
  if not (public.is_admin() or public.owns_news(n.season_id, n.region_id)) then
    raise exception 'Bu bülteni düzenleme yetkiniz yok.';
  end if;
  if v_url is not null and v_url !~* 'instagram\.com/([A-Za-z0-9_.]+/)?(p|reel|reels|tv)/[A-Za-z0-9_-]+' then
    raise exception 'Geçerli bir Instagram gönderisi ya da Reels bağlantısı gir.';
  end if;
  update public.news
     set auto_data = case when v_url is null then auto_data - 'instagram_url'
                          else jsonb_set(auto_data, '{instagram_url}', to_jsonb(v_url)) end
   where id = p_news_id;
end;
$$;
revoke all on function public.set_week_awards_instagram(uuid, text) from public, anon;
grant execute on function public.set_week_awards_instagram(uuid, text) to authenticated;
