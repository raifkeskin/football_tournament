-- Canlı kura haberi, kura bittikten 3 gün sonra yayından kalkar
-- (saatlik pg_cron görevi).

create or replace function public.expire_live_draw_news()
returns integer
language sql
security definer
set search_path to ''
as $$
  with x as (
    update public.news n
       set is_published = false
      from public.live_draws d
     where n.live_draw_id = d.id
       and n.is_published
       and d.end_at < now() - interval '3 days'
    returning n.id
  )
  select count(*)::integer from x;
$$;

revoke all on function public.expire_live_draw_news() from public, anon, authenticated;

select cron.unschedule('live-draw-news-expiry')
where exists (select 1 from cron.job where jobname = 'live-draw-news-expiry');
select cron.schedule('live-draw-news-expiry', '7 * * * *',
                     'select public.expire_live_draw_news()');
