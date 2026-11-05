-- Röportaj / video haberleri test süresince admin ve o turnuvanın kurucu
-- başkanına görünür (bölge sorumlusu ve diğerleri görmez).
create or replace function public.video_news_visible(p_auto_kind text, p_season uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select p_auto_kind is null
      or p_auto_kind not in ('interviews', 'video')
      or public.owns_season(p_season)
      or coalesce((select value = 'true'::jsonb from public.app_settings
                    where key = 'video_news_public'), false)
$$;
grant execute on function public.video_news_visible(text, uuid) to anon, authenticated;

drop policy if exists news_read on public.news;
create policy news_read on public.news for select using (
  public.video_news_visible(auto_kind, season_id) and (
    public.owns_news(season_id, region_id)
    or (is_published
        and (publish_until is null or publish_until > now())
        and public.can_view_season(season_id))
  )
);
drop function if exists public.video_news_visible(text);
