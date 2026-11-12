-- Haftanın Enleri: her enin kendi Instagram gönderisi / Reels bağlantısı
-- (yayından sonra eklenir; enin kartının 2. sayfası olarak gösterilir).
create or replace function public.set_week_award_instagram(p_news_id uuid, p_kind text, p_url text)
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
     set auto_data = jsonb_set(auto_data, '{awards}', coalesce((
       select jsonb_agg(
                case when a->>'kind' = p_kind then
                  case when v_url is null then a - 'instagram_url'
                       else jsonb_set(a, '{instagram_url}', to_jsonb(v_url)) end
                else a end
                order by ord)
         from jsonb_array_elements(auto_data->'awards') with ordinality as t(a, ord)
     ), '[]'::jsonb))
   where id = p_news_id;
end;
$$;
revoke all on function public.set_week_award_instagram(uuid, text, text) from public, anon;
grant execute on function public.set_week_award_instagram(uuid, text, text) to authenticated;
