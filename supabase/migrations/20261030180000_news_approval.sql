-- Otomatik maç sonucu / hafta özeti haberi onaya düşer (news_approval_enabled
-- açıkken): yayın dışı oluşur, admin / kurucu başkan / bölge sorumlusu
-- manşeti düzenleyip yayınlar. 2 saatte onaylanmazsa kendiliğinden yayınlanır.

insert into public.app_settings (key, value)
values ('news_approval_enabled', 'false'::jsonb)
on conflict (key) do nothing;

alter table public.news add column if not exists pending_until timestamptz;

create or replace function public.news_hold_for_approval()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.auto_kind in ('match_result', 'week_results')
       and coalesce(new.is_published, false)
       and coalesce((select s.value = 'true'::jsonb from public.app_settings s
                      where s.key = 'news_approval_enabled'), false) then
      new.is_published := false;
      new.pending_until := now() + interval '2 hours';
    end if;
  elsif coalesce(new.is_published, false)
        and not coalesce(old.is_published, false) then
    -- Yayınlandı (onay ya da süre doldu): bekleme biter.
    new.pending_until := null;
  end if;
  return new;
end;
$$;

drop trigger if exists news_hold_for_approval on public.news;
create trigger news_hold_for_approval
  before insert or update of is_published on public.news
  for each row execute function public.news_hold_for_approval();

-- Süresi dolan bekleyen haberler yayınlanır (maç sonucu ise maç hâlâ
-- bitmiş olmalı; geri alınan maçın haberi bekler).
create or replace function public.publish_due_news()
returns void
language sql
security definer
set search_path to ''
as $$
  update public.news n
     set is_published = true
   where n.pending_until is not null
     and n.pending_until <= now()
     and not n.is_published
     and not n.auto_hidden
     and (n.auto_kind <> 'match_result'
          or exists (select 1 from public.matches m
                      where m.id = n.match_id and m.status = 'finished'
                        and m.deleted_at is null));
$$;

revoke all on function public.publish_due_news() from public, anon, authenticated;

select cron.unschedule('news-auto-publish')
 where exists (select 1 from cron.job where jobname = 'news-auto-publish');
select cron.schedule('news-auto-publish', '*/5 * * * *',
  'select public.publish_due_news()');
