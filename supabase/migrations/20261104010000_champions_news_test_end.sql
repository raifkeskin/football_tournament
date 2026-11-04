-- Test bitti: Champions haber gizleme kuralı kalkar, haberler herkese açılır.
drop policy if exists news_read on public.news;
create policy news_read on public.news for select using (
  public.owns_news(season_id, region_id)
  or (is_published
      and (publish_until is null or publish_until > now())
      and public.can_view_season(season_id))
);
drop function if exists public._test_hidden_news(uuid, timestamptz);
