-- GEÇİCİ (2026-11-03 test): 23:00 sonrası Champions haberleri yayında
-- kalır (uygulama akışı yalnız yayındakileri çeker) ama yalnız haber
-- sahipleri (admin + turnuva yöneticileri) okuyabilir.
drop trigger if exists news_test_hide_champions on public.news;
drop function if exists public._test_hide_champions_news();

create or replace function public._test_hidden_news(p_season_id uuid, p_created timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_created >= timestamptz '2026-11-03 23:00+03'
     and exists (select 1 from public.seasons s
                   join public.leagues l on l.id = s.league_id
                  where s.id = p_season_id
                    and l.name ilike 'champions master league')
$$;

drop policy if exists news_read on public.news;
create policy news_read on public.news for select using (
  public.owns_news(season_id, region_id)
  or (is_published
      and (publish_until is null or publish_until > now())
      and public.can_view_season(season_id)
      and not public._test_hidden_news(season_id, created_at))
);

update public.news n set is_published = true
  from public.seasons s join public.leagues l on l.id = s.league_id
 where s.id = n.season_id and l.name ilike 'champions master league'
   and n.created_at >= timestamptz '2026-11-03 23:00+03';
