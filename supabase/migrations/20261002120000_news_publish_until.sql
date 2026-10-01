-- ============================================================================
-- Haberlere yayın bitiş tarihi. Dolu ise o andan sonra haber herkese kapanır
-- (pasife düşer); turnuva sahibi ve admin görmeye devam eder.
-- ============================================================================

alter table public.news
  add column if not exists publish_until timestamptz;

grant insert (publish_until), update (publish_until)
  on public.news to authenticated;

drop policy if exists news_read on public.news;
create policy news_read on public.news
  for select
  using (
    (is_published and (publish_until is null or publish_until > now()))
    or public.owns_league(league_id)
  );
