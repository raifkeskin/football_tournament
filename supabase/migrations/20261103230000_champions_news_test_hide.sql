-- GEÇİCİ (2026-11-03 test): Champions'ta 23:00'dan (TR) sonra girilen
-- haberler yayında görünmez; yalnız haber sahipleri (admin + turnuva
-- yöneticileri) görür. Test bitince 20261103230100 ile kaldırılır.
create or replace function public._test_hide_champions_news()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.created_at >= timestamptz '2026-11-03 23:00+03'
     and exists (select 1 from public.seasons s
                   join public.leagues l on l.id = s.league_id
                  where s.id = new.season_id
                    and l.name ilike 'champions master league') then
    new.is_published := false;
  end if;
  return new;
end $$;

drop trigger if exists news_test_hide_champions on public.news;
create trigger news_test_hide_champions
  before insert or update on public.news
  for each row execute function public._test_hide_champions_news();

update public.news n set is_published = false
  from public.seasons s join public.leagues l on l.id = s.league_id
 where s.id = n.season_id and l.name ilike 'champions master league'
   and n.created_at >= timestamptz '2026-11-03 23:00+03';
